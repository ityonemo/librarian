defmodule SSH.SCP.Send do
  @moduledoc """
  implements the data transactions involved in a SCP file transfer to the
  destination server.
  """

  require Logger

  @behaviour SSH.ModuleApi

  @impl true
  @spec init(SSH.Stream.t, {Path.t, String.t | iodata, integer}) ::
    {:ok, SSH.Stream.t} | {:error, String.t}
  def init(stream, {filename, content, perms}) do
    size = find_size(content)
    # in order to kick off the SCP routine, we need to send the commence SCP
    # signal to the current process' message mailbox.
    SSH.Stream.send_data(stream,
      "C0#{Integer.to_string(perms, 8)} #{size} #{filename}\n")
    {:ok, %{stream | data: content}}
  end

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

  defp find_size(content) when is_binary(content), do: :erlang.size(content)
  defp find_size([a | b]), do: find_size(a) + find_size(b)

  def reducer(error = {:error, _}, :ok), do: error
  def reducer({:stderr, stderr}, acc) do
    IO.write(:stderr, stderr)
    acc
  end
  def reducer(_, acc), do: acc
end
