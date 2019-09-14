defmodule SSH.Stream do

  # TODO: rename "new" to "build"

  import Logger

  @enforce_keys [:conn, :chan, :stop_time, :process]
  defstruct [:conn, :chan, :stop_time, :process, control: false, halt: false]

  @type conn :: SSH.conn
  @type chan :: :ssh_connection.channel

  @type t :: %__MODULE__{
    conn: conn,
    chan: chan,
    stop_time: DateTime.t,
    # TODO: spec this VV out better
    process: (non_neg_integer, String.t -> any),
    control: boolean,
    halt: boolean
  }

  @spec new(conn, keyword) :: t
  def new(conn, options \\ []) do
    timeout = Keyword.get(options, :timeout, :infinity)
    control = Keyword.get(options, :control, false)
    stop_time = case timeout do
      :infinity -> :infinity
      delta_t when is_integer(delta_t) ->
        DateTime.add(DateTime.utc_now, timeout, :millisecond)
    end

    process = processor_for(options)

    # open a channel.
    # TODO: do a better matching on this.
    {:ok, chan} = :ssh_connection.session_channel(conn, timeout)
    cond do
      cmd = options[:cmd] ->
        # TODO: punt this to the Chan module.
        :success = :ssh_connection.exec(conn, chan, String.to_charlist(cmd), timeout)
        # note that this is a "stateful modification" on the chan reference.
        %__MODULE__{conn: conn, chan: chan, stop_time: stop_time,
          process: process, control: control}
    end
  end

  @spec next_stream(t) :: {list, t}
  def next_stream(state = %{halt: true}) do
    {:halt, state}
  end
  def next_stream(state = %{conn: conn}) do
    timeout = milliseconds_left(state.stop_time)

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
      after timeout ->
        # TODO: cleanup this by emitting a close signal.
        {[{:error, :timeout}], %{state | halt: true}}
    end
  end

  def milliseconds_left(:infinity), do: :infinity
  def milliseconds_left(stop_time) do
    time = DateTime.diff(stop_time, DateTime.utc_now, :millisecond)
    if time > 0, do: time, else: 0
  end

  def last_stream(chan) do
    # TODO: clean up channel resources here.
    chan
  end

  #TODO: change all "state" to "stream"

  defp process_packet(stream = %{chan: chan}, {:data, chan, dtype, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    {stream.process.(dtype, data), stream}
  end
  defp process_packet(stream = %{chan: chan}, {:eof, chan}) do
    {control(stream, :eof), stream}
  end
  defp process_packet(stream = %{chan: chan}, {:exit_status, chan, status}) do
    {control(stream, {:retval, status}), stream}
  end
  defp process_packet(stream = %{chan: chan}, {:closed, chan}) do
    {:halt, stream}
  end
  defp process_packet(stream, packet) do
    wrong_source(stream, packet, "unexpected_channel: #{elem packet, 2}")
  end

  defp control(%{control: true}, v), do: [v]
  defp control(_, _v), do: []

  #TODO: tag log messages with SSH metadata.
  defp wrong_source(stream, packet, msg) do
    Logger.warn("ssh packet of type #{elem packet, 1} received from #{msg}")
    {[], stream}
  end

  defp processor_for(options) do
    stdout_processor = get_processor(options[:stdout], :stdout)
    stderr_processor = get_processor(options[:stderr], :stderr)
    fn
      0, content -> stdout_processor.(content)
      1, content -> stderr_processor.(content)
    end
  end

  defp get_processor(func, _) when is_function(func, 1) do
    fn {_, content} -> func.(content) end
  end
  defp get_processor(:stream, _), do: &[&1]
  defp get_processor(:stdout, _), do: &silent(IO.write(&1))
  defp get_processor(:stderr, _), do: &silent(IO.write(:stderr, &1))
  defp get_processor(:raw, device), do: &[{device, &1}]
  defp get_processor({:file, path}, _) do
    # TODO: we should probably clean up this file descriptor later.
    {:ok, fd} = File.open(path, [:append])
    &to_file(&1, fd)
  end
  # stdout defaults to send to the stream and stderr defaults to print to stderr
  defp get_processor(_, :stdout), do: get_processor(:stream, :stdout)
  defp get_processor(_, :stderr), do: get_processor(:stderr, :stderr)

  @spec to_file(String.t, atom | pid) :: []
  defp to_file(content, fd), do: silent(IO.write(fd, content))

  @spec silent(any) :: []
  defp silent(_), do: []

  defimpl Enumerable do
    def reduce(stream, acc, fun) do
      Stream.resource(
        fn -> stream end,
        &SSH.Stream.next_stream/1,
        &SSH.Stream.last_stream/1
      ).(acc, fun)
    end

    def count(_stream), do: {:error, __MODULE__}

    def member?(_stream, _term), do: {:error, __MODULE__}

    def slice(_stream), do: {:error, __MODULE__}
  end

  defimpl Collectable do
    def into(stream) do
      collector_fun = fn
        str, {:cont, content} ->
          # TODO: error handling here
          :ssh_connection.send(str.conn, str.chan, content)
          str
        str, :done ->
          :ssh_connection.send_eof(str.conn, str.chan)
          str
        _set, :halt -> :ok
      end

      {stream, collector_fun}
    end
  end
end
