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

    fn -> :crypto.strong_rand_bytes(1024) end
    |> Stream.repeatedly
    |> Stream.take(1024) # 1 MB
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

  @scptxt1 "/tmp/scp_test_1.txt"
  test "streaming a list to stdin over the connection is possible" do
    File.rm_rf!(@scptxt1)

    "localhost"
    |> SSH.connect!
    |> SSH.send!(["foo", "bar"], @scptxt1)

    Process.sleep(100)

    assert "foobar" == File.read!(@scptxt1)
  end

  @scptxt2 "/tmp/scp_test_2.txt"
  test "streaming an improper list to stdin over the connection is possible" do
    File.rm_rf!(@scptxt2)

    "localhost"
    |> SSH.connect!
    |> SSH.send!(["foo" | "bar"], @scptxt2)

    Process.sleep(100)

    assert "foobar" == File.read!(@scptxt2)
  end

  # STILL ASPIRATIONAL.  To be implemented in the future.
  #@scptxt3_src "/tmp/scp_test_3_src"
  #@scptxt3_dst "/tmp/scp_test_3_dst"
  #@tag :one
  #test "streaming a file over the connection is possible" do
  #  File.rm_rf!(@scptxt3_src)
  #  File.rm_rf!(@scptxt3_src)
#
  #  #fn -> :crypto.strong_rand_bytes(1024) end
  #  #|> Stream.repeatedly
  #  #|> Stream.take(10) # 10 KB
  #  #|> Enum.into(File.stream!(@scptxt3_src))
#
  #  File.write(@scptxt3_src, "foo")
#
  #  File.read!(@scptxt3_src)
  #  |> fn bytes -> :crypto.hash(:sha256, bytes) end.()
  #  |> Base.encode64
#
  #  "localhost"
  #  |> SSH.connect!
  #  |> SSH.send!(File.stream!(@scptxt3_src, [], 1024), @scptxt3_dst)
#
  #  Process.sleep(100)
#
  #  File.read!(@scptxt3_dst)
  #  |> fn bytes -> :crypto.hash(:sha256, bytes) end.()
  #  |> Base.encode64
  #end

end
