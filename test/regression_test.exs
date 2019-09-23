defmodule LibrarianTest.RegressionTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  # identified 16 Sep 2019, in a project using
  # this as dev mode.  Unexpected packets arrive
  # because the stream exits without clearing
  # eof, exit_status, or closed, when you're using
  # the stream as an input.

  @testpath1 "/tmp/test_path_1"

  @tag :one
  test "stream used as input leaks extra stuff" do
    File.rm_rf!(@testpath1)

    Process.sleep(20)

    conn = SSH.connect!("localhost")

    refute capture_log(fn ->
      SSH.send!(conn, "test_content", @testpath1)
      SSH.run!(conn, "echo hello")
    end) =~ "unexpected"
  end

end
