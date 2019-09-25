defmodule SSH do
  @moduledoc """
  """

  @behaviour SSH.Api

  require Logger

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
  @type connect_result :: {:ok, SSH.conn} | {:error, any}
  @impl true
  @spec connect(remote, keyword) :: connect_result
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

  # TODO: consider moving this out to a different module.
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

  @type retval :: 0..255
  @type run_content :: iodata | {String.t, String.t}
  @doc """
  some documentation about the "run" command
  """
  @type run_result :: {:ok, run_content, retval} | {:error, term}
  @impl true
  @spec run(conn, String.t, keyword) :: run_result
  def run(conn, cmd, options \\ []) do
    options! = Keyword.put(options, :control, true)
    {cmd!, options!} = adjust_run(cmd, options!)

    conn
    |> SSH.Stream.new([{:cmd, cmd!} | options!])
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

  # TODO: consider moving this out to its own module.
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

  #############################################################################
  ## SCP MODE: sending

  # TODO: make this work with iodata

  @doc """
  sends binary content to the remote host.

  Under the hood, this uses the scp protocol to transfer files.

  Protocol is as follows:
  - execute `scp` remotely in the undocumented `-t <destination>` mode
  - send a control string `"C0<perms> <size> <filename>"`
  - wait for single zero byte
  - send the binary data + terminating zero
  - wait for single zero byte
  - send `EOF`

  The perms term should be in octal, and the filename should be rootless.

  options:
  - `:permissions` - sets unix-style permissions on the file.  Defaults to `0o644`

  Example:
  ```
  SSH.send(conn, "foo", "path/to/desired/file")
  ```
  """
  @type send_result :: :ok | {:error, term}
  @impl true
  @spec send(conn, String.t, Path.t, keyword) :: send_result
  def send(conn, content, remote_file, options \\ []) do
    perms = Keyword.get(options, :permissions, 0o644)
    size = :erlang.size(content)
    filename = Path.basename(remote_file)
    SSH.Stream.new(conn,
      cmd: "scp -t #{remote_file}",
      stdout: &process_scp_send(&1, &2),
      init: &init_scp_send(&1,
        "C0#{Integer.to_string(perms, 8)} #{size} #{filename}\n",
        content))
    |> Stream.run
    # TODO: replace this with "ssh stream reducer"
    :ok
  end

  @spec send!(conn, iodata, Path.t, keyword) :: :ok | no_return
  def send!(conn, content, remote_file, options \\ []) do
    case send(conn, content, remote_file, options) do
      :ok -> :ok
      _ -> raise "error"
    end
  end

  defp init_scp_send(stream, init, content) do
    send(self(), {:ssh_send, init})
    {func, _} = stream.stdout
    %{stream | stdout: {func, content},
               packet_timeout: 100,
               packet_timeout_fn: &SSH.SCPState.timeout_handler/1}
  end

  defp process_scp_send(<<0>>, content) when is_binary(content) do
    send(self(), {:ssh_send, content})
    {[], :end}
  end
  defp process_scp_send(<<0>>, :end) do
    # in the case of the scp_send we need to send out the EOF message ourselves.
    send(self(), :ssh_eof)
    {[], :end}
  end
  defp process_scp_send(<<0>> <> rest, any) do
    # sometimes the remote side will get overeager and send "other information
    # our way.  Go ahead and ignore these single-byte zeros.
    process_scp_send(rest, any)
  end
  defp process_scp_send(<<1, error :: binary>>, _) do
    send(self(), :ssh_eof)
    Logger.error(error)
    {[], :end}
  end
  defp process_scp_send(<<2, error :: binary>>, _) do
    # apparently OpenSSH "never sends" fatal error packets.  Just in case the
    # specs change, we should handle this condition
    send(self(), :ssh_eof)
    Logger.error("fatal error: #{error}")
    {[], :end}
  end

  #############################################################################
  ## SCP MODE: fetching

  @doc """
  retrieves a binary file from the remote host.

  Under the hood, this uses the scp protocol to transfer files.

  Protocol is as follows:
  - execute `scp` remotely in the undocumented `-f <source>` mode
  - send a single zero byte to initiate the conversation
  - wait for a control string `"C0<perms> <size> <filename>"`
  - send a single zero byte
  - wait for the binary data + terminating zero
  - send a single zero byte

  The perms term should be in octal, and the filename should be rootless.

  options:
  - `:permissions` - sets unix-style permissions on the file.  Defaults to `0o644`

  Example:
  ```
  SSH.fetch(conn, "path/to/desired/file")
  ```
  """

  @type fetch_result :: {:ok, binary} | {:error, term}
  @impl true
  @spec fetch(conn, Path.t, keyword) :: fetch_result
  def fetch(conn, remote_file, _options \\ []) do
    binary_result = conn
    |> SSH.Stream.new(cmd: "scp -f #{remote_file}",
                      stdout: &process_scp_fetch/1,
                      init: &init_scp_fetch/1)
    |> Enum.reduce(%SSH.SCPState{}, &SSH.SCPState.stream_reducer/2)
    |> Map.get(:content)
    |> :erlang.iolist_to_binary

    {:ok, binary_result}
  end

  def fetch!(conn, remote_file, options \\ []) do
    case fetch(conn, remote_file, options) do
      {:ok, result} -> result
      # TODO: better raise result below.
      _ -> throw "oops"
    end
  end

  defp init_scp_fetch(stream) do
    send(self(), {:ssh_send, <<0>>})
    stream
  end

  defp process_scp_fetch(content) do
    send(self(), {:ssh_send, <<0>>})
    [content]
  end

  @spec stream!(conn, String.t, keyword) :: SSH.Stream.t
  def stream!(conn, cmd, options \\ []) do
    SSH.Stream.new(conn, [{:cmd, cmd} | options])
  end

  @doc """
  closes the ssh connection
  """
  @spec close(conn) :: :ok
  def close(conn), do: :ssh.close(conn)

end
