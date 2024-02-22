defmodule SSH.SCP.Stream do
  @moduledoc """
  implements the data transactions involved in streaming a file to
  the the destination server.

  Concretely, the following functions are implemented:
  - `init/2`, for `c:SSH.ModuleApi.init/2`
  - `on_stdout/2`, for `c:SSH.ModuleApi.on_stdout/2`
  - `on_stderr/2`, for `c:SSH.ModuleApi.on_stderr/2`
  """

  defstruct [:total, so_far: 0, finished: false]

  require Logger

  @behaviour SSH.ModuleApi

  @doc false
  def scp_init(conn, chan, init_invocation) do
    :ssh_connection.send(conn, chan, init_invocation)

    receive do
      {:ssh_cm, ^conn, {:data, ^chan, 0, content}} ->
        scp_process_init(content)

      any ->
        Logger.error("unexpected scp response obtained: #{inspect(any)}")
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
  @spec init(SSH.Stream.t(), any) :: SSH.Stream.t()
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
  @spec on_stderr(term, SSH.Stream.t()) :: {[term], SSH.Stream.t()}
  def on_stderr(string, stream), do: {[stderr: string], stream}

  @impl true
  @spec on_timeout(SSH.Stream.t()) :: {[], SSH.Stream.t()}
  def on_timeout(stream) do
    SSH.Stream.send_data(stream, <<0>>)
    {[], stream}
  end

  @doc false
  def on_stream_done(stream = %{data: :finished}) do
    SSH.Stream.send_eof(stream)
  end

  def on_stream_done(stream = %{conn: conn, chan: chan}) do
    receive do
      {:ssh_cm, ^conn, {:data, ^chan, 0, <<0>>}} ->
        SSH.Stream.send_eof(stream)

      any ->
        Logger.error("unexpected scp response obtained: #{inspect(any)}")
        {:error, "unexpected scp response"}
    after
      stream.data_timeout ->
        SSH.Stream.send_eof(stream)
    end
  end
end
