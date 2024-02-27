defmodule SSHTest.LinkTest do
  use ExUnit.Case, async: true

  @localhost {127, 0, 0, 1}

  def forever do
    receive do
      any -> any
    end
  end

  test "if you link a process with an ssh conn the process will die if the ssh dies" do
    test_pid = self()

    spawn_pid =
      spawn(fn ->
        conn = SSH.connect!(@localhost, link: true)
        send(test_pid, {:ssh, conn})
        forever()
      end)

    conn =
      receive do
        {:ssh, conn} -> conn
      end

    assert Process.alive?(spawn_pid)
    assert Process.alive?(conn)

    Process.exit(conn, :kill)

    Process.sleep(100)

    refute Process.alive?(conn)
    refute Process.alive?(spawn_pid)
  end

  test "if you link a process with an ssh conn the ssh conn will die with the process" do
    test_pid = self()

    spawn_pid =
      spawn(fn ->
        ssh_pid = SSH.connect!(@localhost, link: true)
        send(test_pid, {:ssh, ssh_pid})
        forever()
      end)

    ssh_pid =
      receive do
        {:ssh, ssh_pid} -> ssh_pid
      end

    assert Process.alive?(spawn_pid)

    Process.exit(spawn_pid, :kill)

    Process.sleep(100)

    refute Process.alive?(ssh_pid)
  end
end
