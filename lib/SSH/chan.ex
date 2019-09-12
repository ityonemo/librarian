defmodule SSH.Chan do
  @moduledoc false

  @enforce_keys [:conn, :chan]
  defstruct [:conn, :chan]

  @type conn :: SSH.conn
  @type t :: %__MODULE__{
    conn: conn,
    chan: :ssh_connection.channel_id
  }

  # TODO: tighten up the error type here.
  @spec open(conn, keyword) :: {:ok, t} | {:error, any}
  def open(conn, options) do
    timeout = options[:timeout] || :infinity

    case :ssh_connection.session_channel(conn, timeout) do
      {:ok, chan} ->
        {:ok, %__MODULE__{conn: conn, chan: chan}}
      error -> error
    end
  end

  # TODO: fill this out.

  #def exec(chan) do
  #  case :ssh_connection.exec()
  #end
end
