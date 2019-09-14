defmodule SSHTest.RunOptionsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  describe "when executing SSH.run!/3" do
    test "we can send standard out to the console" do
      test_pid = self()
      assert "foo" <> _ = capture_io(fn ->
        test_run = "localhost"
        |> SSH.connect!
        |> SSH.run!("echo foo", stdout: :stdout)

        send(test_pid, {:result, test_run})
      end)
      assert_receive {:result, ""}
    end

    test "standard error defaults to the stderr" do
      test_pid = self()
      assert "foo" <> _ = capture_io(:stderr, fn ->
        test_run = "localhost"
        |> SSH.connect!
        |> SSH.run!("echo foo 1>&2")

        send(test_pid, {:result, test_run})
      end)
      assert_receive {:result, ""}
    end

    @tmp_file "/tmp/std_out_pipe"
    test "we can send standard out to a file" do
      File.rm_rf!(@tmp_file)

      test_run = "localhost"
      |> SSH.connect!
      |> SSH.run!("echo foo; sleep 0.1; echo bar", stdout: {:file, @tmp_file})

      assert "" == test_run
      assert "foo\nbar\n" == File.read!(@tmp_file)
    end

    test "we can tee sneakily using a stdout function" do
      test_pid = self()
      capture_io(fn ->
        test_run = "localhost"
        |> SSH.connect!
        |> SSH.run!("echo foo", stdout: fn content ->
          IO.write(content)
          [content]
        end)
        send(test_pid, {:result, test_run})
      end)

      assert_receive {:result, "foo\n"}
    end

    test "we can get standard io (both out and err) as a tuple" do
      test_run = "localhost"
      |> SSH.connect!
      |> SSH.run!("echo foo 1>&2; echo bar", io_tuple: true)

      assert {"bar\n", "foo\n"} == test_run
    end

    test "we can get standard out as an iolist" do
      test_run = "localhost"
      |> SSH.connect!
      |> SSH.run!("echo foo; sleep 0.1; echo bar", as: :iolist)

      assert is_list(test_run)
      assert "foo\nbar\n" == :erlang.iolist_to_binary(test_run)
    end

    test "we can send standard error to the stream" do
      test_run = "localhost"
      |> SSH.connect!
      |> SSH.run!("echo foo 1>&2", stderr: :stream)
      |> String.trim

      assert test_run == "foo"
    end

    test "a nonexistent command causes a throw" do
      assert capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          "localhost"
          |> SSH.connect!
          |> SSH.run!("foobar")
        end
      end) =~ "foobar"
    end

    test "a failing command causes a throw" do
      assert_raise RuntimeError, fn ->
        "localhost"
        |> SSH.connect!
        |> SSH.run!("false")
      end
    end
  end

end
