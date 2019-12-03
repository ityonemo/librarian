defmodule SSHTest.EnvTest do

  # NB this feature is not usable until ERL-1107 is resolved (http://bugs.erlang.org/browse/ERL-1107)

  #use ExUnit.Case, async: true

  #describe "when executing SSH.run" do
  #  @describetag :one
  #  test "we can send environment variables as an atom list" do
  #    conn = SSH.connect!("localhost")
  #    assert SSH.run!(conn, "echo $foo", env: [foo: "bar"]) =~ "bar"
  #  end
#
  #  test "we can send environment variables as string prop list" do
  #    conn = SSH.connect!("localhost")
  #    assert SSH.run!(conn, "echo $foo", env: [{"foo", "bar"}]) =~ "bar"
  #  end
  #end
end
