defmodule SSH.SCP.Send do
  @moduledoc """
  implements the data transactions involved in a SCP file transfer to the
  destination server.

  Concretely, the following functions are implemented:
  - `init/2`, for `c:SSH.ModuleApi.init/2`
  - `on_stdout/2`, for `c:SSH.ModuleApi.on_stdout/2`
  - `on_stderr/2`, for `c:SSH.ModuleApi.on_stderr/2`
  """

  require Logger
  @logger_metadata Application.get_env(:librarian, :scp_metadata, [scp: true])

  @behaviour SSH.ModuleApi

  @doc """
  initializes the sending procedure for SCP.

  Expects the following information:
  - the initialized SSH Stream.  This will be modified to include our payload.
  - a triple of: `{remote_filepath, data_content, permissions}`  Permissions should
    be standard unix permissions scheme, for example `0o644` gives read and write
    permissions for the owner, and read permissions for everyone else, or `0o400`
    makes it read-only and only readable to the owner.

  The following tasks are performed:
  - As per the SCP protocol, send the control command: `C0<permissions> <size>
    <remote_filepath>\n`.
  - stash the content in the `:data` field of the stream.

  """
  @impl true
  @spec init(SSH.Stream.t, {Path.t, String.t | iodata, integer}) :: {:ok, SSH.Stream.t}
  def init(stream, {filepath, content, perms}) do
    size = find_size(content)
    # in order to kick off the SCP routine, we need to send the commence SCP
    # signal to the current process' message mailbox.
    SSH.Stream.send_data(stream,
      "C0#{Integer.to_string(perms, 8)} #{size} #{filepath}\n")
    {:ok, %SSH.Stream{stream | data: content}}
  end

  @doc """
  responds to information returned on the `stdout` channel
  by the `scp -t` command.

  As per the protocol the following binary responses can be expected:

  - `<<0>>`: connection acknowledged, send data.
  - `<<0>>`: data packet receieved, send more data.
  - `<<1, error_string>>`: some error has occurred.
  - `<<2, error_string>>`: some fatal error has occurred.


  """
  @impl true
  @spec on_stdout(binary, SSH.Stream.t) :: {[term], SSH.Stream.t}
  def on_stdout(<<0>>, stream = %{data: content})
        when is_binary(content) or is_list(content) do
    SSH.Stream.send_data(stream, content)
    {[], %{stream | data: :finished}}
  end
  def on_stdout(<<0>>, stream = %{data: :finished}) do
    SSH.Stream.send_eof(stream)
    {[], %{stream | data: :finished}}
  end
  def on_stdout(<<0>> <> rest, stream) do
    on_stdout(rest, stream)
  end
  def on_stdout(<<1, error::binary>>, stream) do
    SSH.Stream.send_eof(stream)
    Logger.error("error: #{error}", @logger_metadata)
    {[error: error], %{stream | data: :finished}}
  end
  def on_stdout(<<2, error::binary>>, stream) do
    # apparently OpenSSH "never sends" fatal error packets.  Just in case the
    # specs change, or client is connecting into a differnt SSH server,
    # we should handle this condition
    SSH.Stream.send_eof(stream)
    emsg = "fatal error: #{error}"
    Logger.error(emsg, @logger_metadata)
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

  defp find_size(content) when is_binary(content), do: :erlang.size(content)
  defp find_size([a | b]), do: find_size(a) + find_size(b)

  def reducer(error = {:error, _}, :ok), do: error
  def reducer({:stderr, stderr}, acc) do
    IO.write(:stderr, stderr)
    acc
  end
  def reducer(_, acc), do: acc
end
