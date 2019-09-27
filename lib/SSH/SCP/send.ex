defmodule SSH.SCP.Send do
  @moduledoc false

  # this library defines the SCP "send" protocol, in terms of a SSH-stream module.

  require Logger

  @behaviour SSH.ModuleApi

  @type acc :: String.t | iodata | :finished

  @impl true
  @spec init(SSH.Stream.t, {Path.t, String.t | iodata, integer}) ::
    {:ok, acc} | {:error, String.t}
  def init(_, {filename, content, perms}) do
    size = find_size(content)
    # in order to kick off the SCP routine, we need to send the commence SCP
    # signal to the current process' message mailbox.
    send(self(), {:ssh_send, "C0#{Integer.to_string(perms, 8)} #{size} #{filename}\n"})
    {:ok, content}
  end

  @impl true
  @spec stdout(term, acc) :: {[term], acc}
  def stdout(<<0>>, content) when is_binary(content) or is_list(content) do
    send(self(), {:ssh_send, content})
    {[], :finished}
  end
  def stdout(<<0>>, :finished) do
    send(self(), :ssh_eof)
    {[], :finished}
  end
  def stdout(<<0>> <> rest, any) do
    stdout(rest, any)
  end
  def stdout(<<1, error::binary>>, _) do
    send(self(), :ssh_eof)
    Logger.error("error: #{error}")
    {[error: error], :finished}
  end
  def stdout(<<2, error::binary>>, _) do
    # apparently OpenSSH "never sends" fatal error packets.  Just in case the
    # specs change, or client is connecting into a differnt SSH server,
    # we should handle this condition
    send(self(), :ssh_eof)
    emsg = "fatal error: #{error}"
    Logger.error(emsg)
    # go ahead and crash the process when this happens
    raise SSH.SCP.FatalError, message: emsg
  end

  @impl true
  @spec stderr(term, acc) :: {[term], acc}
  def stderr(string, acc), do: {[stderr: string], acc}

  @impl true
  @spec packet_timeout(acc) :: {[], acc}
  def packet_timeout(acc) do
    send(self(), {:ssh_send, <<0>>})
    {[], acc}
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
