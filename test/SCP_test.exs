defmodule SSHTest.SCPTest do
  use ExUnit.Case, async: true

  @content "foo\nbar\n"

  @tmp_ssh_fetch "/tmp/ssh_fetch.txt"
  test "we can do an scp" do
    File.write!(@tmp_ssh_fetch, @content)

    conn = SSH.connect!("localhost")
    assert @content == SSH.fetch!(conn, @tmp_ssh_fetch)
  end

  @tmp_ssh_send "/tmp/ssh_send.txt"
  test "we can send an scp" do
    File.rm_rf!(@tmp_ssh_send)
    conn = SSH.connect!("localhost")
    SSH.send!(conn, @content, @tmp_ssh_send)

    assert @content == File.read!(@tmp_ssh_send)
  end
end
