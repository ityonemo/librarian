defmodule SSH.Stream do

  @moduledoc """
  Defines an `SSH.Stream` struct returned by `SSH.stream!/3`

  Like `IO.Stream`, an SSH stream has side effects.  Any given
  time you use it, the contents returned are likely to be different.
  """

  require Logger
  @logger_metadata Application.get_env(:librarian, :ssh_metadata, [ssh: true])

  @enforce_keys [:conn, :chan, :stop_time]
  defstruct [:conn, :chan, :on_stdout, :on_stderr, :on_timeout, :stop_time, :fds, :data,
    stream_control_messages: false,
    halt: false,
    data_timeout: :infinity,
  ]

  # TODO: spec out any is the same way as below:
  @type process_fn :: (String.t -> any) | (String.t, term -> {list, term})

  @type t :: %__MODULE__{
    conn: SSH.conn,
    chan: SSH.chan,
    stop_time: DateTime.t,
    fds: [],
    stream_control_messages: boolean,
    halt: boolean,
    on_stdout: process_fn,
    on_stderr: process_fn,
    on_timeout: (t -> {list, t}),
    data_timeout: timeout,
    data: any
  }

  defp module_overlay(nil), do: []
  defp module_overlay({module, init_param}) do

    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        :ok
      _ ->
        raise ArgumentError, "module #{module} doesn't exist"
    end

    Enum.flat_map([init: 2, on_stdout: 2, on_stderr: 2, on_timeout: 1],
      fn {fun, arity} ->
        if function_exported?(module, fun, arity) do
          [{fun, :erlang.make_fun(module, fun, arity)}]
        else
          []
        end
      end)
    |> Keyword.put(:init_param, init_param)
  end

  @spec __build__(SSH.conn, keyword) :: {:ok, t} | {:error, String.t}
  def __build__(conn, options \\ []) do

    # make sure a command exists.
    options[:cmd] || raise ArgumentError, "you must supply a command for SSH."

    options = [ #default options
      init:                    &default_init/2,
      conn_timeout:            options[:timeout] || :infinity,
      data_timeout:            :infinity,
      stream_control_messages: false,
      fds:                     fds_for(options),
      on_stdout:               get_processor(options[:stdout], :stdout),
      on_stderr:               get_processor(options[:stderr], :stderr),
      on_timeout:              options[:on_timeout] || &default_timeout/1]
    |> Keyword.merge(options)
    |> Keyword.merge(module_overlay(options[:module]))

    timeout = options[:conn_timeout] || :infinity

    stop_time = case timeout do
      :infinity                        -> :infinity
      delta_t when is_integer(delta_t) ->
        DateTime.add(DateTime.utc_now, delta_t, :millisecond)
    end

    # open a channel.
    with {:ok, chan} <- :ssh_connection.session_channel(conn, timeout),
         :success <- :ssh_connection.exec(conn, chan, String.to_charlist(options[:cmd]), timeout) do

      mergeable_options = options
      |> Keyword.take([:on_stdout, :on_stderr, :on_timeout, :stream_control_messages, :fds, :data_timeout])
      |> Enum.into(%{})

      options[:init].(
        %__MODULE__{conn: conn, chan: chan, stop_time: stop_time}
        |> Map.merge(mergeable_options),
        options[:init_param])
    end
  end

  # TODO: handle halts

  defp default_init(stream, _), do: {:ok, stream}
  defp default_timeout(stream), do: {:halt, stream}

  @spec next_stream(t) :: {list, t}
  def next_stream(stream = %{halt: true}) do
    {:halt, stream}
  end
  def next_stream(stream = %{conn: conn}) do
    connection_time_left = milliseconds_left(stream.stop_time)

    {timeout, timeout_mode} =
      if connection_time_left < stream.data_timeout do
        # if the connection is about to expire, let that be the timeout,
        # and send an overall timeout message.
        # NB: if both are infinity, this is irrelevant.
        {connection_time_left, :global}
      else
        # if the packet timeout is about to expire, punt to the packet
        # timeout handler.
        {stream.data_timeout, :data}
      end

    receive do
      # a ssh "packet" should arrive as a message to this process since it has
      # been registered with the :ssh module subsystem.
      {:ssh_cm, ^conn, packet} ->
        process_message(stream, packet)

      # if the chan and conn values don't match, then we should drop the packet
      # and issue a warning.
      {:ssh_cm, wrong_conn, packet} ->
        wrong_source(stream, packet,
          "unexpected connection: #{inspect wrong_conn}")

      # TODO: change it so that stream_data_timeout_fn always has
      # at least a null function in there.

      after timeout ->
        {conn, timeout, timeout_mode}
        case timeout_mode do
          :global -> {[error: :timeout], %{stream | halt: true}}
          :data -> stream.on_timeout.(stream)
        end
    end
  end

  @spec send_data(t, iodata) :: :ok
  @doc """
  sends an iodata payload to the stdin of the ssh stream

  You should use this method inside of stderr, stdout, and data_timeout
  functions when you're designing interactive ssh handlers.  Note that this
  function must be called from within the same process that the stream is
  running on, while the stream is running.

  In the future, we might write a guard that will prevent you from
  doing this from another process.
  """
  def send_data(stream, payload) do
    send(self(), {:ssh_cm, stream.conn, {:send, stream.chan, payload}})
    :ok
  end

  @spec send_eof(t) :: :ok
  @doc """
  sends an end-of-file to the the ssh stream.

  You should use this method inside of stderr, stdout, and data_timeout
  functions when you're designing interactive ssh handlers.  Note that this
  function must be called from within the same process that the stream is
  running on, while the stream is running.

  In the future, we might write a guard that will prevent you from
  doing this from another process.
  """
  def send_eof(stream) do
    send(self(), {:ssh_cm, stream.conn, {:send_eof, stream.chan}})
    :ok
  end

  def milliseconds_left(:infinity), do: :infinity
  def milliseconds_left(stop_time) do
    time = DateTime.diff(stop_time, DateTime.utc_now, :millisecond)
    if time > 0, do: time, else: 0
  end

  defp drain(stream = %{conn: conn, chan: chan}) do
    # drain the last packets.
    receive do
      {:eof, ^conn, {:eof, ^chan}} ->
        drain(stream)
      {:ssh_cm, ^conn, {:exit_status, ^chan, _status}} ->
        drain(stream)
      {:ssh_cm, ^conn, {:closed, ^chan}} ->
        drain(stream)
      after 1 ->
        stream
    end
  end

  @spec last_stream(t) :: :ok
  def last_stream(stream) do
    drain(stream)

    # close out our file descriptors
    if stream.fds do
      Enum.each(stream.fds, fn {_, fd} -> File.close(fd) end)
    end

    # close out the ssh connection
    :ssh_connection.close(stream.conn, stream.chan)
  end

  @typedoc "binary data sent over the server's standard out (0) or standard error (1)"
  @type iostream_message :: {:data, SSH.chan, 0 | 1, binary}

  @typedoc "ssh protocol stream control messages"
  @type control_message :: {:eof, SSH.chan} | {:exit_status, SSH.chan, integer} | {:closed, SSH.chan}

  @typedoc "messages that the local client can use to send streaming content"
  @type outbound_message :: {:send, SSH.chan, binary} | {:send_eof, SSH.chan}

  @typedoc """
  all messages that are blocked by the stream control loop.

  Note that most of these are the third term in a `{:ssh_cm, conn, <message>}` tuple.
  """
  @type ssh_message :: iostream_message | control_message | outbound_message

  @typedoc "the default tokens that can be sent for stream processing"
  @type stream_tokens :: :eof | {:stdout, binary} | {:stderr, binary} | {:stream, binary} | {:retval, integer} | :halt

  @spec process_message(t, ssh_message) :: {[term], t}
  defp process_message(stream = %{chan: chan}, {:data, chan, 0, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    stream.on_stdout.(data, stream)
  end
  defp process_message(stream = %{chan: chan}, {:data, chan, 1, data}) do
    :ssh_connection.adjust_window(stream.conn, chan, byte_size(data))
    stream.on_stderr.(data, stream)
  end
  defp process_message(stream = %{chan: chan}, {:eof, chan}) do
    {filter_control_messages(stream, :eof), stream}
  end
  defp process_message(stream, {:eof, _}) do
    {[], stream}
  end
  defp process_message(stream = %{chan: chan}, {:exit_status, chan, status}) do
    {filter_control_messages(stream, {:retval, status}), stream}
  end
  defp process_message(stream = %{chan: chan}, {:closed, chan}) do
    {:halt, stream}
  end
  defp process_message(stream = %{chan: chan}, {:send, chan, payload}) do
    # TODO: figure out error handling here.
    :ssh_connection.send(stream.conn, stream.chan, payload)
    {[], stream}
  end
  defp process_message(stream = %{chan: chan}, {:send_eof, chan}) do
    # TODO: figure out what to do with this.
    :ssh_connection.send_eof(stream.conn, stream.chan)
    {[], stream}
  end
  defp process_message(stream, packet) when is_tuple(packet) do
    wrong_source(stream, packet, "unexpected channel: #{elem packet, 1}")
  end

  # TODO: do a better job of describing term below:
  @spec filter_control_messages(t, term) :: [term]
  defp filter_control_messages(%{stream_control_messages: true}, v), do: [v]
  defp filter_control_messages(_, _v), do: []

  defp wrong_source(stream, packet, msg) do
    Logger.warn("ssh packet of type #{elem packet, 0} received from #{msg}", @logger_metadata)
    {[], stream}
  end

  ###################################################################
  ## stream data processor selection

  # convert a user specified arity/1 value into an arity/2  with passthrough on value 2
  defp get_processor(fun, _) when is_function(fun, 1), do: fn val, any -> {fun.(val), any} end
  defp get_processor(fun, _) when is_function(fun, 2), do: fun
  defp get_processor(:stream, _), do: fn value, any -> {[value], any} end
  defp get_processor(:stdout, _), do: &silent(IO.write(&1), &2)
  defp get_processor(:stderr, _), do: &silent(IO.write(:stderr, &1), &2)
  defp get_processor(:raw, device), do: &{[{device, &1}], &2}
  defp get_processor(:silent, _), do: &silent/2
  defp get_processor({:file, _}, channel), do: &silent(IO.write(&2.fds[channel], &1), &2)
  # default processors, if we take a nil in the first term.
  defp get_processor(nil, :stdout), do: get_processor(:stream, :stdout) # send stdout to the stream.
  defp get_processor(nil, :stderr), do: get_processor(:stderr, :stderr) # send stderr to stderr

  @spec silent(any, SSH.Stream.t) :: {[], SSH.Stream.t}
  defp silent(_, stream), do: {[], stream}

  ###################################################################
  ## file descriptor things

  defp fds_for(options) do
    Enum.flat_map(options, fn
      {mode, {:file, path}} ->
        case File.open(path, [:append]) do
          {:ok, fd} -> [{mode, fd}]
          _ ->
            raise File.Error, path: path
        end
      _ -> []
    end)
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
