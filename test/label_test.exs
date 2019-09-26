defmodule SSHTest.LabelTest do
  use ExUnit.Case, async: true

  test "labelling your ssh connections works" do
    {:ok, conn} = SSH.connect("localhost", label: "foo")
    {:ok, "bar\n", 0} = SSH.run(conn, "echo bar")
    :ok = SSH.close("foo")

    #wait a bit before closing.
    Process.sleep(10)

    refute Process.alive?(conn)
  end

  def bad_process do
    with {:ok, conn} <- SSH.connect("localhost", label: :foo),
         _ <- send(self(), {:conn, conn}),
         {:ok, _res1, 0} <- SSH.run(conn, "this_is_not_a_command", stderr: :silent),
         {:ok, _res2, 0} <- SSH.run(conn, "echo bar") do
      send(self(), :unreachable)
    end
  after
    SSH.close(:foo)
  end

  test "this can be used to escape a with block" do
    assert {:ok, _, retval} = bad_process()
    refute retval == 0

    Process.sleep(10)
    assert_receive {:conn, conn}
    refute Process.alive?(conn)

    refute_receive :unreachable
  end

end
