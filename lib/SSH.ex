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

  | ssh commandline option    | SSH library option            |
  | ------------------------- | ----------------------------- |
  | `-o NoStrictHostChecking` | `silently_accept_hosts: true` |
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
      reraise SSH.ConnectionError, "error connecting to #{remote}"
  end

  def run(conn, cmd!, options! \\ []) do
    options! = Keyword.put(options!, :control, true)
    {cmd!, options!} = adjust_run(cmd!, options!)

    conn
    |> stream(cmd!, options!)
    |> Enum.to_list
    |> Enum.reduce({:error, [], nil}, &consume/2)
    |> normalize_output(options!)
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

  defp consume(str, {status, list, retval}) when is_binary(str), do: {status, [list | str], retval}
  defp consume(token = {a, b}, {status, list, retval}) when is_atom(a) and is_binary(b) do
    {status, [token | list], retval}
  end
  defp consume(:eof, {_any, list, retval}), do: {:ok, list, retval}
  defp consume({:error, reason}, {_status, list, _any}), do: {:error, list, reason}
  defp consume({:retval, retval}, {status, list, _any}), do: {status, list, retval}

  defp normalize_output({a, list, b}, options) do
    case options[:as] do
      nil -> {a, :erlang.iolist_to_binary(list), b}
      :binary -> {a, :erlang.iolist_to_binary(list), b}
      :iolist -> {a, list, b}
      :tuple ->
        tuple_map = list
        |> Enum.reverse
        |> Enum.group_by(fn {key, _} -> key end, fn {_, value} -> value end)

        result = {
          :erlang.iolist_to_binary(tuple_map.stdout),
          :erlang.iolist_to_binary(tuple_map.stderr)
        }

        {a, result, b}
    end
  end

  defp adjust_run(cmd, options) do
    dir = options[:dir]
    if dir do
      {"cd #{dir}; " <> cmd, refactor(options)}
    else
      {cmd, refactor(options)}
    end
  end
  defp refactor(options) do
    if options[:io_tuple] do
      options
      |> Keyword.drop([:stdout, :stderr, :io_tuple, :as])
      |> Keyword.merge(stdout: :raw, stderr: :raw, as: :tuple)
    else
      options
    end
  end

  @spec stream(conn, String.t, keyword) :: SSH.Stream.t
  def stream(conn, cmd, options \\ []) do
    SSH.Stream.new(conn, [{:cmd, cmd} | options])
  end

end
