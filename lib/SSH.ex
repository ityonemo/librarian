defmodule SSH do
  @moduledoc """

  SSH streams and SSH and basic SCP functionality

  The librarian SSH module provides SSH streams (see `stream/3`) and
  three protocols over the SSH stream:

  - `run/3`, which runs a command on the remote SSH host.
  - `fetch/3`, which uses the SCP protocol to obtain a remote file,
  - `send/4`, which uses the SCP protocol to send a file to the remote host.

  Note that not all SSH hosts (for example, embedded shells), implement an
  SCP command, so you may not necessarily be able to perform SCP over your
  SSH stream.

  ## Using SSH

  The principles of this library are simple.  You will first want to create
  an SSH connection using the `connect/2` function.  There you will provide
  credentials (or let the system figure out the default credentials).  The
  returned `conn` term can then be passed to the multiple utilities.

  ```elixir
  {:ok, conn} = SSH.connect("some.other.server")
  SSH.run!(conn, "echo hello ssh")  # ==> "hello ssh"
  ```

  ## Mocking

  There's a good chance you'll want to mock your SSH commands and responses.
  The `SSH.Api` behaviour module is provided for that purpose.

  ## Logging

  The SSH and related modules interface with Elixir (and Erlang's) logging
  facility.  The default metadata tagged on the message is `ssh: true`; if
  you would like to set it otherwise you can set the `:librarian, :ssh_metadata`
  application environment variable.

  ## Customization

  If you would like to write your own SSH stream handlers that plug in to
  the SSH stream and provide either rudimentary interactivity or early stream
  token processing, you may want to consider implementing a module following
  the `SSH.ModuleApi` behaviour, and initiating your stream as desired.

  ## Limitations

  This library has largely been tested against Linux SSH clients.  Not all
  SSH schemes are amenable to stream processing.  In those cases you should
  implement an ssh client gen_server using erlang's ssh_client, though
  support for this in elixir is planned in the near-term.
  """

  @behaviour SSH.Api

  alias SSH.SCP.Fetch
  alias SSH.SCP.Send

  require Logger

  #############################################################################
  ## generally useful types

  @typedoc "erlang ip4 format, `{byte, byte, byte, byte}`"
  @type ip4 :: :inet.ip4_address

  @typedoc "connect to a remote is specified using either a domain name or an ip address"
  @type remote :: String.t | charlist | ip4

  @typedoc "connection reference for the SSH and SCP operations"
  @type conn :: :ssh.connection_ref

  @typedoc "channel reference for the SSH and SCP operations"
  @type chan :: :ssh.channel_id

  #############################################################################
  ## connection and stream handling

  @typedoc false
  @type connect_result :: {:ok, SSH.conn} | {:error, any}

  @doc """
  initiates an ssh connection with a remote server.

  ### options:

  - `login:` username to log in.
  - `port:`  port to use to ssh, defaults to 22.
  - `label:` see [labels](#connect/2-labels)

  and other SSH options.  Some conversions between ssh options and SSH.connect
  options:

  | ssh commandline option    | SSH library option            |
  | ------------------------- | ----------------------------- |
  | `-o NoStrictHostChecking` | `silently_accept_hosts: true` |

  ### labels:

  You can label your ssh connection to provide a side-channel for
  correctly closing the connection pid.  This is most useful in
  the context of `with/1` blocks.  As an example, the following
  code works:

  ```elixir
  def run_ssh_tasks do
    with {:ok, conn} <- SSH.connect("some_host", label: :this_task),
         {:ok, _result1, 0} <- SSH.run(conn, "some_command"),
         {:ok, result2, 0} <- SSH.run(conn, "some other command") do
      {:ok, result1}
    end
  after
    SSH.close(:this_task)
  end
  ```

  Some important points:
  - The connection label may be any term except for a `pid` or `nil`
  - If you are wrangling multiple SSH sessions, please use unique connection
    labels.
  - The ssh connection label is stored in the process mailbox, so the label
    will not be valid across process boundaries.
  """
  @impl true
  @spec connect(remote, keyword) :: connect_result
  def connect(remote, options \\ [])
  def connect(remote, options) when is_list(remote) do

    login = normalize(options[:login])
    port = options[:port] || 22

    new_options = options
    |> Keyword.merge(login)
    |> Keyword.drop([:port, :login, :label])

    remote
    |> :ssh.connect(port, new_options)
    |> stash_label(options[:label])
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

  @spec stash_label({:ok, conn} | {:error, any}, term) :: {:ok, conn} | {:error, any} | no_return
  defp stash_label(res, nil), do: res
  defp stash_label(_, pid) when is_pid(pid) do
    raise ArgumentError, "you can't make a pid label for an SSH connection."
  end
  defp stash_label(res = {:ok, conn}, label) do
    send(self(), {:"$ssh", label, conn})
    res
  end
  defp stash_label(res, _), do: res

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
  like `connect/2` but raises with a ConnectionError instead of emitting an error tuple.
  """
  @impl true
  @spec connect!(remote, keyword) :: conn | no_return
  def connect!(remote, options \\ []) do
    case connect(remote, options) do
      {:ok, conn} -> conn
      {:error, message} ->
        raise SSH.ConnectionError, "error connecting to #{remote}: #{message}"
    end
  end

  # TODO: Doc this
  @doc """
  creates an SSH stream struct as an ok tuple or error tuple.
  """
  @spec stream(conn, String.t, keyword) :: {:ok, SSH.Stream.t} | {:error, String.t}
  def stream(conn, cmd, options \\ []) do
    SSH.Stream.__build__(conn, [{:cmd, cmd} | options])
  end

  @doc """
  like `stream/2`, except raises on an error instead of an error tuple.
  """
  @spec stream!(conn, String.t, keyword) :: SSH.Stream.t | no_return
  def stream!(conn, cmd, options \\ []) do
    case stream(conn, cmd, options) do
      {:ok, stream} -> stream
      {:error, error} ->
        raise SSH.StreamError, message: "error creating ssh stream: #{error}"
    end
  end

  @doc """
  closes the ssh connection.

  Typically you will pass the connection reference to this function.  If your
  connection is contained to its own transient task process, you may not need
  to call this function as the ssh client library will detect that the process
  has ended and clean up after you.

  In some cases, you may want to be able to close a connection out-of-band.
  In this case, you may label your connection and use the label to perform
  the close operation.  See [labels](#connect/2-labels)
  """
  @impl true
  @spec close(conn | term) :: :ok | {:error, String.t}
  def close(conn) when is_pid(conn), do: :ssh.close(conn)
  def close(label) do
    receive do
      {:"$ssh", ^label, pid} ->
        :ssh.close(pid)
      after 0 ->
        {:error, "ssh connection with label #{label} not found"}
    end
  end

  #############################################################################
  ## SSH MODE: running

  @typedoc "unix-style return codes for ssh-executed functions"
  @type retval :: 0..255

  @typedoc false
  @type run_content :: iodata | {String.t, String.t}

  @typedoc false
  @type run_result :: {:ok, run_content, retval} | {:error, term}

  # TODO: doc this
  @doc """
  some documentation about the "run" command
  """
  @impl true
  @spec run(conn, String.t, keyword) :: run_result
  def run(conn, cmd, options \\ []) do
    options! = Keyword.put(options, :stream_control_messages, true)
    {cmd!, options!} = adjust_run(cmd, options!)

    with {:ok, stream} <- SSH.Stream.__build__(conn, [{:cmd, cmd!} | options!]) do
      stream
      |> Enum.reduce({:error, [], nil}, &consume/2)
      |> normalize_output(options!)
    end
  end

  @impl true
  @spec run!(conn, String.t, keyword) :: run_content | no_return
  def run!(conn, cmd, options \\ []) do
    case run(conn, cmd, options) do
      {:ok, result, 0} -> result
      {:ok, _result, retcode} ->
        raise "command errored with retcode #{retcode}"
      error ->
        raise "ssh errored with #{inspect(error)}"
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
          :erlang.iolist_to_binary(tuple_map[:stdout] || []),
          :erlang.iolist_to_binary(tuple_map[:stderr] || [])
        }

        {a, result, b}
    end
  end
  defp normalize_output(error, _options), do: error

  defp adjust_run(cmd, options) do
    # drop any naked as: :tuple pairs.
    options! = options -- [as: :tuple]

    dir = options![:dir]
    if dir do
      {"cd #{dir}; " <> cmd, refactor(options!)}
    else
      {cmd, refactor(options!)}
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
  # TODO: check that the permissions part is OK.

  @typedoc false
  @type send_result :: :ok | {:error, term}

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
  @impl true
  @spec send(conn, String.t, Path.t, keyword) :: send_result
  def send(conn, content, remote_file, options \\ []) do
    perms = Keyword.get(options, :permissions, 0o644)
    filename = Path.basename(remote_file)
    initializer = {filename, content, perms}

    case SSH.Stream.__build__(conn,
        cmd: "scp -t #{remote_file}",
        module: {Send, initializer},
        data_timeout: 500) do
      {:ok, stream} ->
        Enum.reduce(stream, :ok, &Send.reducer/2)
      error -> error
    end
  end

  @doc """
  like `send/4`, except raises on errors, instead of returning an error tuple.
  """
  @impl true
  @spec send!(conn, iodata, Path.t) :: :ok | no_return
  @spec send!(conn, iodata, Path.t, keyword) :: :ok | no_return
  def send!(conn, content, remote_file, options \\ []) do
    case send(conn, content, remote_file, options) do
      :ok -> :ok
      {:error, message} ->
        raise SSH.SCP.Error, "error executing SCP send: #{message}"
    end
  end

  #############################################################################
  ## SCP MODE: fetching

  @typedoc false
  @type fetch_result :: {:ok, binary} | {:error, term}

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
  @impl true
  @spec fetch(conn, Path.t, keyword) :: fetch_result
  def fetch(conn, remote_file, _options \\ []) do
    with {:ok, stream} <- SSH.Stream.__build__(conn,
                            cmd: "scp -f #{remote_file}",
                            module: {Fetch, :ok},
                            data_timeout: 500) do
      Enum.reduce(stream, :ok, &Fetch.reducer/2)
    end
  end

  @doc """
  like `fetch/3` except raises instead of emitting an error tuple.
  """
  @impl true
  @spec fetch!(conn, Path.t, keyword) :: binary | no_return
  def fetch!(conn, remote_file, options \\ []) do
    case fetch(conn, remote_file, options) do
      {:ok, result} -> result
      {:error, message} ->
        raise SSH.SCP.Error, "error executing SCP send: #{message}"
    end
  end

end

defmodule SSH.StreamError do
  defexception [:message]
end
