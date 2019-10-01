defmodule SSH.Api do
  @moduledoc """
  You might want to run mocked tests against a component that uses the SSH Api.
  Here is provided the behaviour module to support this testing pattern.

  generally speaking, these sorts of features should not be using the
  quick-and-dirty banged commands, so only the api for the fully error-tupled
  forms is provided.
  """

  @callback connect(SSH.remote, keyword) :: SSH.connect_result
  @callback connect(SSH.remote) :: SSH.connect_result

  @callback connect!(SSH.remote, keyword) :: :ok | no_return
  @callback connect!(SSH.remote) :: :ok | no_return

  @callback run(SSH.conn, String.t, keyword) :: SSH.run_result
  @callback run(SSH.conn, String.t) :: SSH.run_result

  @callback run!(SSH.conn, String.t, keyword) :: iodata | {String.t, String.t}
  @callback run!(SSH.conn, String.t) :: iodata | {String.t, String.t}

  @callback fetch(SSH.conn, Path.t, keyword) :: SSH.fetch_result
  @callback fetch(SSH.conn, Path.t) :: SSH.fetch_result

  @callback fetch!(SSH.conn, Path.t, keyword) :: binary | no_return
  @callback fetch!(SSH.conn, Path.t) :: binary | no_return

  @callback send(SSH.conn, iodata, Path.t, keyword) :: SSH.send_result
  @callback send(SSH.conn, iodata, Path.t) :: SSH.send_result

  @callback send!(SSH.conn, iodata, Path.t, keyword) :: :ok | no_return
  @callback send!(SSH.conn, iodata, Path.t) :: :ok | no_return

  @callback close(term) :: :ok | {:error, String.t}

end
