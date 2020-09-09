defmodule SSH.SCP.Fetch do
  @moduledoc """
  implements the data transactions involved in streaming SCP file transfer
  *from* the destination server.

  Concretely, the following functions are implemented:
  - `init/2`, for `c:SSH.ModuleApi.init/2`
  - `on_stdout/2`, for `c:SSH.ModuleApi.on_stdout/2`
  - `on_stderr/2`, for `c:SSH.ModuleApi.on_stderr/2`
  """

  require Logger

  @behaviour SSH.ModuleApi

  @impl true
  @doc "initializes the fetching procedure for SCP"
  @spec init(SSH.Stream.t, any) :: {:ok, SSH.Stream.t} | {:error, String.t}
  def init(stream, _) do
    # in order to kick off the SCP routine, we need to send an ready message,
    # which is simply a "0" byte over the standard out.
    SSH.Stream.send_data(stream, <<0>>)
    {:ok, stream}
  end

  @impl true
  @doc "responds to information returned on the `stderr` stream by the `scp -f` command"
  @spec on_stdout(binary, SSH.Stream.t) :: {[], SSH.Stream.t}
  def on_stdout("C0" <> <<_perms :: binary-size(3)>> <> _rest, stream) do
    SSH.Stream.send_data(stream, <<0>>)
    {[], stream}
  end
  def on_stdout(value, stream) do
    # store all inbound values into the stream.
    SSH.Stream.send_data(stream, <<0>>)
    {[value], stream}
  end

  @impl true
  @doc "responds to information returned on the `stdout` stream by the `scp -f` command"
  @spec on_stderr(binary, SSH.Stream.t) :: {[term], SSH.Stream.t}
  def on_stderr(string, stream), do: {[stderr: string], stream}

  @impl true
  @doc "handles the remote `scp` agent not calling back"
  @spec on_timeout(SSH.Stream.t) :: {[], SSH.Stream.t}
  def on_timeout(stream) do
    SSH.Stream.send_data(stream, <<0>>)
    {[], stream}
  end

  @doc false
  def reducer(value, :ok) when is_binary(value) do
    # TODO: don't use string.trim for this because String module expects
    # unicode data.
    {:ok, String.trim(value, <<0>>)}
  end
  def reducer(value, {:ok, previous}) when is_binary(value) do
    # TODO: don't use string.trim for this because String module expects
    # unicode data.
    {:ok, previous <> String.trim(value, <<0>>)}
  end

end
