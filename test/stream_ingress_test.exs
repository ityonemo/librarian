defmodule SSHTest.StreamIngressTest do
  use ExUnit.Case, async: true

  @footxt "/tmp/foo.txt"
  test "streaming to stdin over the connection is possible" do

    File.rm_rf!(@footxt)

    ssh_stream = "localhost"
    |> SSH.connect!
    |> SSH.stream("tee #{@footxt} | wc -m")

    output = ["foo"]
    |> Enum.into(ssh_stream)
    |> Enum.to_list
    |> :erlang.iolist_to_binary
    |> String.trim

    assert "3" == output
  end

end
