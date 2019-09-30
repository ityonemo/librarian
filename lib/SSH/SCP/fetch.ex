defmodule SSH.SCP.Fetch do
  @moduledoc false

  # this library defines the SCP "send" protocol, in terms of a SSH-stream module.

  require Logger

  @behaviour SSH.ModuleApi

  # TODO: implement hostile scp values testing.

  @impl true
  @spec init(SSH.Stream.t, any) :: {:ok, SSH.Stream.t} | {:error, String.t}
  def init(stream, _) do
    # in order to kick off the SCP routine, we need to send an ready message,
    # which is simply a "0" byte over the standard out.
    SSH.Stream.send_data(stream, <<0>>)
    {:ok, stream}
  end

  #TODO : work with the rest of the stuff here!

  @impl true
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
  @spec on_stderr(binary, SSH.Stream.t) :: {[term], SSH.Stream.t}
  def on_stderr(string, stream), do: {[stderr: string], stream}

  @impl true
  @spec on_timeout(SSH.Stream.t) :: {[], SSH.Stream.t}
  def on_timeout(stream) do
    SSH.Stream.send_data(stream, <<0>>)
    {[], stream}
  end

  def reducer(value, :ok) when is_binary(value) do
    {:ok, String.trim(value, <<0>>)}
  end
  def reducer(value, {:ok, previous}) when is_binary(value) do
    {:ok, previous <> String.trim(value, <<0>>)}
  end

end
