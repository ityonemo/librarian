defmodule SSH.Stream do

  import Logger

  alias SSH.{Conn, Chan}

  @enforce_keys [:chan]
  defstruct [:chan]

  @type t :: %__MODULE__{}

  @type conn :: SSH.conn
  @type chan :: Chan.t

  @spec new(conn, keyword) :: t
  def new(conn, options \\ []) do
    timeout = options[:timeout] || :infinity
    # open a channel.
    # TODO: do a better matching on this.
    {:ok, chan} = Chan.open(conn, options) |> IO.inspect(label: "20")
    options |> IO.inspect(label: "21")
    cond do
      cmd = options[:cmd] ->
        # TODO: punt this to the Chan module.
        :success = :ssh_connection.exec(conn, chan.chan, String.to_charlist(cmd), timeout)
        # note that this is a "stateful modification" on the chan reference.
        %__MODULE__{chan: chan}
    end
  end

  @spec next_stream(chan) :: {list, chan}
  def next_stream(state = %{conn: conn}) do
    receive do
      # a ssh "packet" should arrive as a message to this process
      # since it has been registered with the :ssh module subsystem.
      {:ssh_cm, ^conn, packet} ->
        process_packet(state, packet)
      # if the chan and conn values don't match, then we should drop
      # the packet and issue a warning.
      {:ssh_cm, wrong_conn, packet} ->
        wrong_source(state, packet, "unexpected_connection: #{inspect wrong_conn}")
      # if we run out of time, we should emit a warning and halt the stream.
    end
  end

  def last_stream(chan) do
    # TODO: clean up channel resources here.
    chan
  end

  defp process_packet(state = %{chan: chan}, {:data, chan, dtype, data}) do
    :ssh_connection.adjust_window(state.conn, chan, byte_size(data))
    case dtype do
      0 ->
        {[{:stdout, data}], state}
      1 ->
        {[{:stderr, data}], state}
    end
  end
  defp process_packet(state = %{chan: chan}, {:eof, chan}) do
    {[:eof], state}
  end
  defp process_packet(state = %{chan: chan}, {:exit_status, chan, status}) do
    {[{:retval, status}], state}
  end
  defp process_packet(state = %{chan: chan}, {:closed, chan}) do
    {:halt, state}
  end
  defp process_packet(state, packet) do
    wrong_source(state, packet, "unexpected_channel: #{elem packet, 2}")
  end

  #TODO: tag log messages with SSH metadata.
  defp wrong_source(state, packet, msg) do
    Logger.warn("ssh packet of type #{elem packet, 1} received from #{msg}")
    {[], state}
  end

  defimpl Enumerable do

    # TODO: consider writing a more idiomatic version of this
    # using a state machine once the tests have been written.
    def reduce(stream, acc, fun) do
      Stream.resource(
        fn -> stream.chan end,
        &SSH.Stream.next_stream/1,
        &SSH.Stream.last_stream/1
      ).(acc, fun)
    end

    def count(_stream), do: {:error, __MODULE__}

    def member?(_stream, _term), do: {:error, __MODULE__}

    def slice(_stream), do: {:error, __MODULE__}
  end
end
