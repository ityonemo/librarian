defmodule SSH.Config do

  @default_global_config_path "/etc/ssh/ssh_config"
  @default_user_config_path "~/.ssh/config"

  @moduledoc """
  handles parsing of SSH configuration files.

  obtains configuration as follows:

  - check the global config file, set by `Application.put_env(:librarian, :global_config_file, <file>)`,
    or defaults to `#{@default_global_config_path}`.  Alternatively
    may be set as an option in the `load/1` function. You may suppress this
    by setting either the application environment variable or the option to
    `false`.  This path must be an absolute path.

  - check the user config file, set by `Application.put_env(:librarian, :user_config_file, <file>)`,
    or defaults to `#{@default_user_config_path}`.  Alternatively, may
    be set as an option in the `load/1` function.  You may suppress this
    by setting the application environment variable to `false`.  This path
    may be a relative path.

  **warnings**

  - Not all of the SSH options can be honored, only the ones that are supported
    by the erlang `:ssh` module.  Moreover, not all of them have been implemented
    yet.  If you need one, consider submitting a PR or an issue in the issue
    tracker.
  - If your config file contains an alias for a certain activity, such as SSH
    tunneling, the config parser will still honor this alias, but will not provide
    the extra features specified in the config file.  This behavior might
    change in the future or may be accompanied by a warning.
  - wildcard configuration is not supported.
  - argument tokens are not supported.

  Due to these warnings, using configuration is defaulted to `false` in
  `SSH.connect/2`.  This behaviour may change in the future.
  """

  @doc """
  loads SSH configuration text from global and user configuration files.

  Defaults to checking `#{@default_global_config_path}` and
  `#{@default_user_config_path}`.

  ### options
  - `:global_config_path` sets the global config path.  Must be absolute.
    if set to false, will suppress checking global configs.
  - `:user_config_path` sets the user config path.  If set to false, will
    suppress checking local configs.
  """
  @spec load(keyword) :: %{optional(String.t) => map}
  def load(options \\ []) do
    global_config_path = options[:global_config_path] ||
      Application.get_env(
        :librarian,
        :global_config_path,
        @default_global_config_path)

    global_config = if global_config_path && File.exists?(global_config_path) do
      unless match?("/" <> _, global_config_path) do
        raise ArgumentError, "global config path must be absolute."
      end
      global_config_path
      |> File.read!
      |> parse
    else
      %{}
    end

    user_config_path = options[:user_config_path] ||
      Application.get_env(
        :librarian,
        :user_config_Path,
        @default_user_config_path)

    user_config = if user_config_path do
      user_config_abs_path = Path.expand(user_config_path)
      if File.exists?(user_config_abs_path) do
        user_config_abs_path
        |> File.read!
        |> parse
      end
    end

    Map.merge(global_config, user_config || %{})
  end

  @doc """
  parses a configuration text, loaded as a string.
  """
  @spec parse(String.t) :: %{optional(String.t) => map}
  def parse(config_text) do
    config_text
    |> String.split("\n")
    |> Enum.map(&preprocess_line/1)
    |> Enum.reduce({[], nil, nil}, &parse_reducer/2)
    |> complete
  end

  @spec preprocess_line(String.t) :: String.t
  defp preprocess_line(val) do
    val
    |> String.trim
    |> String.split("#", parts: 2) # handle commented lines by splitting and
    |> Enum.at(0)                  # ignoring anything past the octothorpe
  end

  @typep parse_intermediate :: {[{String.t, keyword}], String.t | nil, keyword | nil}

  @spec parse_reducer(String.t, parse_intermediate) :: parse_intermediate
  defp parse_reducer("Host " <> hostname, {kw_so_far, nil, nil}) do
    {kw_so_far, hostname, []}
  end
  defp parse_reducer("Host " <> hostname, {kw_so_far, this_name, this_kw}) do
    {kw_so_far ++ [{this_name, this_kw}], String.trim(hostname), []}
  end
  defp parse_reducer("", acc), do: acc
  defp parse_reducer(_other, {_, nil, nil}), do: raise "error parsing ssh config file, must begin with a Host statement"
  defp parse_reducer(other, acc = {kw_so_far, this_name, this_map}) do
    other
    |> String.split(~r/\s/, parts: 2)
    |> case do
      [string_key, value] ->
        atom_key = string_key |> Macro.underscore |> String.to_atom
        {kw_so_far, this_name, this_map ++ [{atom_key, value}]}
      [""] -> acc
      [string] -> raise "error parsing ssh config: stray config #{string}"
    end
  end

  @spec complete(parse_intermediate) :: %{optional(String.t) => map}
  defp complete({_, nil, nil}), do: %{}
  defp complete({kw_so_far, this_name, this_kw}) do
    kw_so_far
    |> Kernel.++([{this_name, this_kw}])
    |> Enum.map(fn
      {host, kw} ->
        keymap = kw |> Enum.map(&adjust/1) |> Enum.into(%{})
        {host, keymap} end)
    |> Enum.into(%{})
  end

  @boolean_keys [:hash_based_authentication, :strict_host_key_checking]
  @second_keys [:connect_timeout]

  defp adjust({key, v}) when key in @second_keys do
    {key, String.to_integer(v) * 1000}
  end
  defp adjust({key, v}) when key in @boolean_keys do
    {key, boolean(v)}
  end
  defp adjust(any), do: any

  defp boolean("yes"), do: true
  defp boolean("no"), do: false

  #################################################################

  @doc false
  # routine called by SSH.connect/2 to correctly assemble all of
  # the connect options and all of the config options
  @spec assemble(charlist, keyword) :: keyword
  def assemble(remote, options) do
    ssh_options = if options[:use_ssh_config] do
      remote_str = List.to_string(remote)
      options
      |> load
      |> Map.get(remote_str)
    else
      []
    end

    ssh_options
    |> Keyword.merge(options)  # user options take precedence.
    |> Keyword.put_new_lazy(:user, &find_user/0)
    |> rename_to_erlang_ssh
    |> Keyword.put_new(:port, 22)
    |> filter_implemented      # whitelist usable options.
  end

  defp find_user do
    case System.cmd("whoami", []) do
      {username, 0} -> String.trim(username)
      _ -> raise ArgumentError, "no user name supplied and couldn't find a default."
    end
  end

  defp rename_to_erlang_ssh(options) do
    Enum.map(options, fn
      {:strict_host_key_checking, v} -> {:silently_accept_hosts, v}
      {:user, usr} when is_binary(usr) -> {:user, String.to_charlist(usr)}
      any -> any
    end)
  end

  @allowed_options [
    :user, :port, :silently_accept_hosts, :quiet_mode, :connect_timeout
  ]
  defp filter_implemented(options) do
    Enum.filter(options, fn {k, _v} ->
      k in @allowed_options
    end)
  end

end
