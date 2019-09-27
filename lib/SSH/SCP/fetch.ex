defmodule SSH.SCP.Fetch do
  @moduledoc false

  # this library defines the SCP "send" protocol, in terms of a SSH-stream module.

  require Logger

  @behaviour SSH.ModuleApi

  # TODO: implement hostile scp values testing.

  @type acc :: :ok

  @impl true
  @spec init(SSH.Stream.t, any) :: {:ok, acc} | {:error, String.t}
  def init(_, _) do
    # in order to kick off the SCP routine, we need to send an ready message,
    # which is simply a "0" byte over the standard out.
    send(self(), {:ssh_send, <<0>>})
    {:ok, :ok}
  end

  #TODO : work with the rest of the stuff here!

  @impl true
  @spec stdout(binary, acc) :: {[], acc}
  def stdout("C0" <> <<_perms :: binary-size(3)>> <> rest, acc) do
    send(self(), {:ssh_send, <<0>>})
    {[], acc}
  end
  def stdout(value, acc) do
    send(self(), {:ssh_send, <<0>>})
    {[value], acc}
  end

  @impl true
  @spec stderr(binary, acc) :: {[term], acc}
  def stderr(string, acc), do: {[stderr: string], acc}

  @impl true
  @spec packet_timeout(acc) :: {[], acc}
  def packet_timeout(acc) do
    send(self(), {:ssh_send, <<0>>})
    {[], acc}
  end

  def reducer(value, :ok) when is_binary(value) do
    {:ok, String.trim(value, <<0>>)}
  end
  def reducer(value, {:ok, previous}) when is_binary(value) do
    {:ok, previous <> String.trim(value, <<0>>)}
  end

end
