defmodule SSH do
  @moduledoc """
  """

  @type ip4 :: :inet.ip4_address
  @type remote :: String.t | charlist | ip4
  @type conn :: :ssh.connection_ref

  @doc """


  options:

  - `login:` username to log in.
  - `port:`  port to use to ssh, defaults to 22.

  and other SSH options.  Some conversions between ssh options and SSH.connect options:

  | `ssh` option              | `SSH` option                |
  | ------------------------- | --------------------------- |
  | `-o NoStrictremoteChecking` | silently_accept_remotes: true |
  """
  @spec connect(remote, keyword) :: {:ok, conn} | {:error, any}
  def connect(remote, options \\ [])
  def connect(remote, options) when is_list(remote) do

    login = normalize(options[:login])
    port = options[:port] || 22

    new_options = options
    |> Keyword.merge(login)
    |> Keyword.drop([:port, :login])

    :ssh.connect(remote, port, new_options)
  end
  def connect(remote, options) when is_binary(remote) do
    remote
    |> String.to_charlist
    |> connect(options)
  end
  def connect(remote_ip = {_a, _b, _c, _d}, options) do
    remote_ip
    |> :inet.ntoa
    |> connect(options)
  end

  # TODO: rename this.
  @spec normalize(nil | binary | charlist) :: [{:user, charlist}]
  defp normalize(nil) do
    case System.cmd("whoami", []) do
      {username, 0} -> normalize(String.trim(username))
      _ -> []
    end
  end
  defp normalize(str) when is_binary(str), do: [user: String.to_charlist(str)]
  defp normalize(charlist) when is_list(charlist), do: [user: charlist]

  @doc """
  see `connect/2` but raises with a ConnectionError instead of emitting an error tuple.
  """
  @spec connect!(remote, keyword) :: conn | no_return
  def connect!(remote, options \\ []) do
    {:ok, conn} = connect(remote, options)
    conn
  rescue
    _ in MatchError ->
      raise SSH.ConnectionError, "error connecting to #{remote}"
  end

  def run(conn, cmd!, options! \\ []) do
    {cmd!, options!} = adjust_run(cmd!, options!)

    conn
    |> stream(cmd!, options!)
    |> ssh_filter(options!)
  end

  def run!(conn, cmd, options \\ []) do
    case run(conn, cmd, options) do
      {:ok, stdout, 0} -> stdout
      {:ok, _stdout, retcode} ->
        raise "errored with retcode #{retcode}"
      error ->
        raise inspect(error)
    end
  end

  defp adjust_run(cmd, [{:dir, dir} | options]) do
    adjust_run("cd #{dir}; " <> cmd, options)
  end
  defp adjust_run(cmd, options), do: {cmd, options}

  @spec stream(conn, String.t, keyword) :: SSH.Stream.t
  def stream(conn, cmd, options) do
    stream(conn, [{:cmd, cmd} | options])
  end

  @spec stream(conn, String.t | keyword) :: SSH.Stream.t
  def stream(conn, options) when is_list(options) do
    SSH.Stream.new(conn, options)
  end
  def stream(conn, cmd) when is_binary(cmd) do
    SSH.Stream.new(conn, cmd: cmd)
  end

  defp ssh_filter(ssh_stream, _options) do
    ssh_stream
    |> Enum.reduce([], fn
      {:stdout, txt}, acc ->
        [acc | txt]
      {:retval, retval}, acc ->
        {acc, retval}
      _, acc -> acc
    end)
    |> fn
      {iolist, retval} ->
        {:ok, :erlang.iolist_to_binary(iolist), retval}
      iolist when is_list(iolist) ->
        # for now.
        {:error, :erlang.iolist_to_binary(iolist), :timeout}
    end.()
  end

end
