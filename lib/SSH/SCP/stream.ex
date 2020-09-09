defmodule SCP.Stream do
  # handles streaming SCP.

  defstruct [:total, so_far: 0, finished: false]

  require Logger

  @behaviour SSH.ModuleApi

  def consume_stream(conn, fstream = %File.Stream{}, remote_file, options) do
    size = File.stat!(fstream.path).size
    consume_stream(conn, fstream, size, remote_file, options)
  end
  def consume_stream(conn,
        src_stream = %Stream{enum: fstream = %File.Stream{}},
        remote_file,
        options) do

    size = File.stat!(fstream.path).size
    consume_stream(conn, src_stream, size, remote_file, options)
  end

  def consume_stream(conn, src_stream, size, remote_file, options) do
    perms = Keyword.get(options, :permissions, 0o644)

    file_id = Path.basename(remote_file)

    case SSH.Stream.__build__(conn,
        cmd: "scp -t #{remote_file}",
        module: {__MODULE__, {Path.basename(remote_file), size, perms}},
        data_timeout: 500,
        prerun_fn: &scp_init(&1, &2, "C0#{Integer.to_string(perms, 8)} #{size} #{file_id}\n"),
        on_finish: &Function.identity/1,
        on_stream_done: &on_stream_done/1) do

      {:ok, ssh_stream} ->

        src_stream
        |> Enum.into(ssh_stream)
        |> Stream.run

      error -> error
    end
  end

  defp scp_init(conn, chan, init_invocation) do
    :ssh_connection.send(conn, chan, init_invocation)
    receive do
      {:ssh_cm, ^conn, {:data, ^chan, 0, content}} ->
        scp_process_init(content)
      any ->
        Logger.error("unexpected scp response obtained: #{inspect any}")
        :failure
    end
  end

  defp scp_process_init(<<0>>) do
    :success
  end
  defp scp_process_init(<<0>> <> rest) do
    scp_process_init(rest)
  end
  defp scp_process_init(<<1>> <> rest) do
    Logger.error("failure to initialize scp stream: #{rest}")
    :failure
  end
  defp scp_process_init(<<2>> <> rest) do
    raise "fatal failure to initialize scp stream: #{rest}"
  end

  @impl true
  @spec init(SSH.Stream.t, any) :: SSH.Stream.t
  def init(stream, param) do
    {:ok, %{stream | data: param, on_finish: &Function.identity/1}}
  end

  @impl true
  def on_stdout(<<0>>, stream) do
    {[], %{stream | data: :finished}}
  end
  def on_stdout(<<0>> <> rest, stream) do
    on_stdout(rest, %{stream | data: :finished})
  end
  def on_stdout(<<1, error::binary>>, stream) do
    SSH.Stream.send_eof(stream)
    Logger.error("error: #{error}")
    {[error: error], %{stream | data: :finished}}
  end
  def on_stdout(<<2, error::binary>>, stream) do
    # apparently OpenSSH "never sends" fatal error packets.  Just in case the
    # specs change, or client is connecting into a differnt SSH server,
    # we should handle this condition
    SSH.Stream.send_eof(stream)
    emsg = "fatal error: #{error}"
    Logger.error(emsg)
    # go ahead and crash the process when this happens
    raise SSH.SCP.FatalError, message: emsg
  end
  def on_stdout("", stream) do
    SSH.Stream.send_data(stream, <<0>>)
    {[], stream}
  end

  @impl true
  @spec on_stderr(term, SSH.Stream.t) :: {[term], SSH.Stream.t}
  def on_stderr(string, stream), do: {[stderr: string], stream}

  @impl true
  @spec on_timeout(SSH.Stream.t) :: {[], SSH.Stream.t}
  def on_timeout(stream) do
    SSH.Stream.send_data(stream, <<0>>)
    {[], stream}
  end

  defp on_stream_done(stream = %{data: :finished}) do
    SSH.Stream.send_eof(stream)
  end
  defp on_stream_done(stream = %{conn: conn, chan: chan}) do
    receive do
      {:ssh_cm, ^conn, {:data, ^chan, 0, <<0>>}} ->
        SSH.Stream.send_eof(stream)

      any ->
        Logger.error("unexpected scp response obtained: #{inspect any}")
        {:error, "unexpected scp response"}

      after stream.data_timeout ->
        SSH.Stream.send_eof(stream)
    end
  end

end
