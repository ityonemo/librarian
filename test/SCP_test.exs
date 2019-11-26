defmodule SSHTest.SCPTest do
  use ExUnit.Case, async: true

  @moduletag :scp

  @content "foo\nbar\n"

  @tmp_ssh_fetch "/tmp/ssh_fetch.txt"
  test "we can fetch a file with scp" do
    File.write!(@tmp_ssh_fetch, @content)

    conn = SSH.connect!("localhost")
    assert @content == SSH.fetch!(conn, @tmp_ssh_fetch)
    File.rm_rf!(@tmp_ssh_fetch)
  end

  @tmp_ssh_send "/tmp/ssh_send.txt"
  test "we can send an scp" do
    File.rm_rf!(@tmp_ssh_send)
    conn = SSH.connect!("localhost")
    SSH.send!(conn, @content, @tmp_ssh_send)

    assert @content == File.read!(@tmp_ssh_send)
    File.rm_rf!(@tmp_ssh_send)
  end

  @tmp_ssh_big_file "/tmp/ssh_big_file"
  @tmp_ssh_big_sent "/tmp/ssh_big_sent"
  test "we can send a really big file" do
    File.rm_rf!(@tmp_ssh_big_file)
    File.rm_rf!(@tmp_ssh_big_sent)

    fn -> <<Enum.random(0..255)>> end
    |> Stream.repeatedly
    |> Stream.take(1024 * 1024) # 1 MB
    |> Enum.into(File.stream!(@tmp_ssh_big_file))

    src_bin = File.read!(@tmp_ssh_big_file)

    hash = :crypto.hash(:sha256, src_bin)

    "localhost"
    |> SSH.connect!
    |> SSH.send!(src_bin, @tmp_ssh_big_sent)

    res_bin = File.read!(@tmp_ssh_big_sent)

    assert hash == :crypto.hash(:sha256, res_bin)

    File.rm_rf!(@tmp_ssh_big_file)
    File.rm_rf!(@tmp_ssh_big_sent)
  end
end
