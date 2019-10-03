defmodule SSHTest.ConfigTest do

  use ExUnit.Case, async: true

  @basic_config """
  Host foobar
    User baz
    HostName 8.8.8.8
  """

  test "we can pull basic configuration out from a config file" do
    assert %{"foobar" => [
      user: "baz",
      host_name: "8.8.8.8"
    ]} == SSH.Config.parse(@basic_config)
  end

  @all_config """
  Host quux
    User bling
    HostName 4.4.4.4
    IdentityFile ~/.ssh/new_id.pem
    GlobalKnownHostsFile ~/my_hosts_file
    HashBasedAuthentication yes
    ConnectTimeout 10
    StrictHostKeyChecking no
    UserKnownHostsFile ~/user_hosts_file

  Host boo
    User abcd
    HostName test.local
  """

  test "we can pull all the configuration out from config file" do
    assert %{"quux" => [
      user: "bling",
      host_name: "4.4.4.4",
      identity_file: "~/.ssh/new_id.pem",
      global_known_hosts_file: "~/my_hosts_file",
      hash_based_authentication: true,
      connect_timeout: 10_000,
      strict_host_key_checking: false,
      user_known_hosts_file: "~/user_hosts_file"
    ],
    "boo" => [
      user: "abcd",
      host_name: "test.local"]} == SSH.Config.parse(@all_config)
  end

end
