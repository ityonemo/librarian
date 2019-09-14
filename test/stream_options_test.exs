defmodule SSHTest.StreamOptionsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  describe "when executing SSH.stream/3" do
    test "we can send standard out to the console" do
      test_pid = self()
      assert "foo" <> _ = capture_io(fn ->
        test_run = "localhost"
        |> SSH.connect!
        |> SSH.stream("echo foo", stdout: :stdout)
        |> Enum.to_list

        send(test_pid, {:result, test_run})
      end)
      assert_receive {:result, []}
    end

    test "we can get standard out as an iolist" do
      test_run = "localhost"
      |> SSH.connect!
      |> SSH.stream("echo foo; sleep 0.1; echo bar")
      |> Enum.to_list

      assert "foo\nbar\n" == :erlang.iolist_to_binary(test_run)
    end

    test "we can capture both standard error and standard out to the stream" do
      test_run = "localhost"
      |> SSH.connect!
      |> SSH.stream("echo foo 1>&2; sleep 0.1; echo bar", stderr: :stream)
      |> Enum.to_list

      assert :erlang.iolist_to_binary(test_run) == "foo\nbar\n"
    end
  end

end
