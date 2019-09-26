defmodule SSH.Stream do

  # TODO: rename "new" to "build"

  import Logger

  @enforce_keys [:conn, :chan, :stop_time, :stdout, :stderr]
  defstruct [:conn, :chan, :stop_time, :stdout, :stderr, :fds,
    control: false,
    halt: false,
    packet_timeout: :infinity,
    packet_timeout_fn: nil
  ]

  @type conn :: SSH.conn
  @type chan :: :ssh_connection.channel
  # TODO: spec out any is the same way as below:
  @type process_fn :: (String.t -> any) | {(String.t, term -> {any, term}), term}

  @type t :: %__MODULE__{
    conn: conn,
    chan: chan,
    stop_time: DateTime.t,
    fds: [],
    control: boolean,
    halt: boolean,
    stdout: process_fn,
    stderr: process_fn,
    packet_timeout: timeout,
    packet_timeout_fn: (t -> {list | :halt, t})
  }

  @spec __build__(conn, keyword) :: t
  def __build__(conn, options \\ []) do
    timeout = Keyword.get(options, :timeout, :infinity)
    control = Keyword.get(options, :control, false)
    stop_time = case timeout do
      :infinity -> :infinity
      delta_t when is_integer(delta_t) ->
        DateTime.add(DateTime.utc_now, timeout, :millisecond)
    end

    # convert any 'file write' requests to a file descriptor
    fds = fds_for(options)
    # determine the functions which will handle the conversion
    # of inbound ssh data packets to usable forms.
    {stdout, stderr} = processor_for(Keyword.merge(options, fds))

    # set up an initializer function that might modify the stream.
    initializer = Keyword.get(options, :init, &(&1))

    # open a channel.
    # TODO: do a better matching on this.
    {:ok, chan} = :ssh_connection.session_channel(conn, timeout)
    if cmd = options[:cmd] do
        # TODO: punt this to the Chan module.
        :success = :ssh_connection.exec(conn, chan, String.to_charlist(cmd), timeout)
        # note that this is a "stateful modification" on the chan reference.
        initializer.(
          %__MODULE__{conn: conn, chan: chan, stop_time: stop_time,
          stdout: stdout, stderr: stderr, control: control, fds: fds})
    else
      raise ArgumentError, "no command set."
    end
  end

  @spec next_stream(t) :: {list, t}
  def next_stream(state = %{halt: true}) do
    {:halt, state}
  end
  def next_stream(state = %{conn: conn}) do
    connection_time_left = milliseconds_left(state.stop_time)

    {timeout, timeout_fun} =
      if connection_time_left < state.packet_timeout do
        # if the connection is about to expire, let that be the timeout,
        # and send an overall timeout message.
        # NB: if both are infinity, this is irrelevant.
        {connection_time_left, fn -> {[error: :timeout], %{state | halt: true}} end}
      else
        # if the packet timeout is about to expire, punt to the packet
        # timeout handler.
        {state.packet_timeout, fn -> state.packet_timeout_fn.(state) end}
      end

    receive do
      # a ssh "packet" should arrive as a message to this process since it has
      # been registered with the :ssh module subsystem.
      {:ssh_cm, ^conn, packet} ->
        process_packet(state, packet)

      # if the chan and conn values don't match, then we should drop the packet
      # and issue a warning.
      {:ssh_cm, wrong_conn, packet} ->
        wrong_source(state, packet, "unexpected connection: #{inspect wrong_conn}")

      # also allow messages to be SENT along the ssh channel, asynchronously,
      # using erlang messages as a "side channel"
      {:ssh_send, payload} ->
        send_packet(state, payload)

      :ssh_eof ->
        :ssh_connection.send_eof(state.conn, state.chan)
        {[], %{state | halt: true}}

      after timeout ->
        timeout_fun.()
    end
  end

  def milliseconds_left(:infinity), do: :infinity
  def milliseconds_left(stop_time) do
    time = DateTime.diff(stop_time, DateTime.utc_now, :millisecond)
    if time > 0, do: time, else: 0
  end

  # TODO: this is really hacky.  Please review.
  def drain(stream = %{conn: conn, chan: chan}) do
    # drain the last packets.
    receive do
      {:eof, ^conn, {:eof, ^chan}} ->
        drain(stream)
      {:ssh_cm, ^conn, {:exit_status, ^chan, _status}} ->
        drain(stream)
      {:ssh_cm, ^conn, {:closed, ^chan}} ->
        drain(stream)
      after 100 ->
        stream
    end
  end
  def last_stream(stream) do
    drain(stream)
    :ssh_connection.close(stream.conn, stream.chan)
  end

  #TODO: change all "state" to "stream"
  defp process_packet(stream = %{chan: chan, stdout: {fun, state}},
                      {:data, chan, 0, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    {output, new_state} = fun.(data, state)
    {output, %{stream | stdout: {fun, new_state}}}
  end
  defp process_packet(stream = %{chan: chan, stderr: {fun, state}},
                      {:data, chan, 1, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    {output, new_state} = fun.(data, state)
    {output, %{stream | stderr: {fun, new_state}}}
  end
  defp process_packet(stream = %{chan: chan}, {:data, chan, 0, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    {stream.stdout.(data), stream}
  end
  defp process_packet(stream = %{chan: chan}, {:data, chan, 1, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    {stream.stderr.(data), stream}
  end
  defp process_packet(stream = %{chan: chan}, {:eof, chan}) do
    {control(stream, :eof), stream}
  end
  defp process_packet(stream, {:eof, _}) do
    {[], stream}
  end
  defp process_packet(stream = %{chan: chan}, {:exit_status, chan, status}) do
    {control(stream, {:retval, status}), stream}
  end
  defp process_packet(stream = %{chan: chan}, {:closed, chan}) do
    {:halt, stream}
  end
  defp process_packet(stream, packet) do
    wrong_source(stream, packet, "unexpected channel: #{elem packet, 1}")
  end

  defp control(%{control: true}, v), do: [v]
  defp control(_, _v), do: []

  #TODO: tag log messages with SSH metadata.
  defp wrong_source(stream, packet, msg) do
    Logger.warn("ssh packet of type #{elem packet, 0} received from #{msg}")
    {[], stream}
  end

  ###################################################################
  ## stream data processor selection

  defp processor_for(options), do: {
    get_processor(options[:stdout], :stdout),
    get_processor(options[:stderr], :stderr)
  }

  defp get_processor(fun, _) when is_function(fun, 1), do: fun
  defp get_processor(fun, _) when is_function(fun, 2), do: {fun, nil}
  defp get_processor(:stream, _), do: &[&1]
  defp get_processor(:stdout, _), do: &silent(IO.write(&1))
  defp get_processor(:stderr, _), do: &silent(IO.write(:stderr, &1))
  defp get_processor(:raw, device), do: &[{device, &1}]
  defp get_processor(:silent, _), do: &silent/1
  defp get_processor({:file, fd}, _), do: &silent(IO.write(fd, &1))
  # stdout defaults to send to the stream and stderr defaults to print to stderr
  defp get_processor(_, :stdout), do: get_processor(:stream, :stdout)
  defp get_processor(_, :stderr), do: get_processor(:stderr, :stderr)

  @spec silent(any) :: []
  defp silent(_), do: []

  ###################################################################
  ## file descriptor things

  defp fds_for(options) do
    Enum.flat_map(options, fn
      {mode, {:file, path}} ->
        {:ok, fd} = File.open(path, [:append])
        [{mode, {:file, fd}}]
      _ -> []
    end)
  end

  ###################################################################
  ## interactive streaming capabilities

  # TODO: replace "state" everywhere with "stream"
  def send_packet(stream, payload) do
    :ssh_connection.send(stream.conn, stream.chan, payload)
    {[], stream}
  end

  ###################################################################
  ## protocol implementations

  defimpl Enumerable do
    @type stream :: SSH.Stream.t
    @type event :: {:cont, stream} | {:halt, stream} | {:suspend, stream}

    @spec reduce(stream, event, function) :: Enumerable.result
    def reduce(stream, acc, fun) do
      Stream.resource(
        fn -> stream end,
        &SSH.Stream.next_stream/1,
        &SSH.Stream.last_stream/1
      ).(acc, fun)
    end

    @spec count(stream) :: {:error, module}
    def count(_stream), do: {:error, __MODULE__}

    @spec member?(stream, term) :: {:error, module}
    def member?(_stream, _term), do: {:error, __MODULE__}

    @spec slice(stream) :: {:error, module}
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
