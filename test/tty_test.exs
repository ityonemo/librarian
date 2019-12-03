defmodule SSHTest.TTYTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  describe "when executing SSH.run" do
    test "the `tty` command line program runs as expected" do
      conn = SSH.connect!("localhost")
      {:ok, _, x} = SSH.run(conn, "tty")
      assert x != 0

      # check that it defaults to sending to stdout

      assert "/dev/" <> _  = capture_io(fn ->
        assert {:ok, _, 0} = SSH.run(conn, "tty", tty: true)
      end)

      # and it's overrideable, in the normal fashion (say you want to send it to a LiveView)

      assert {:ok, "/dev" <> _, 0} = SSH.run(conn, "tty", tty: true, stdout: :stream)

      # and it's possible to directly send some tty options in.
      assert {:ok, "/dev" <> _, 0} = SSH.run(conn, "tty", tty: [width: 80, height: 40], stdout: :stream)
    end
  end
end
