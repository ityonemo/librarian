defmodule SSHTest.EnvTest do

  # NOTE: this test can't be run unless you have
  # AcceptEnv set in your ssh daemon.

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
