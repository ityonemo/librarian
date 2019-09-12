defmodule SSHTest do
  use ExUnit.Case, async: true

  @moduletag :ssh

  describe "when attempting to use run/3" do
    test "can trigger a program to run" do
      test_run = "localhost"
      |> SSH.connect!
      |> SSH.run!("hostname")
      |> String.trim

      expected_result = "hostname"
      |> System.cmd([])
      |> fn {str, 0} -> String.trim(str) end.()

      assert test_run == expected_result
    end

    #test "can issue run in a directory" do
    #  test_file = UUID.uuid4()
    #  test_content = UUID.uuid4()
#
    #  "/tmp"
    #  |> Path.join(test_file)
    #  |> File.write!(test_content)
#
    #  test_run = "localhost"
    #  |> SSH.connect!
    #  |> SSH.run!("cat #{test_file}", dir: "/tmp")
    #  |> String.trim
#
    #  assert test_run == test_content
    #end
#
    #test "can issue run in a relative-to-home directory" do
    #  test_dir = ("~" <> UUID.uuid4()) |> Path.expand
    #  test_file = UUID.uuid4()
    #  test_content = UUID.uuid4()
#
    #  File.mkdir_p!(test_dir)
#
    #  test_dir
    #  |> Path.join(test_file)
    #  |> File.write!(test_content)
#
    #  test_run = "localhost"
    #  |> SSH.connect!
    #  |> SSH.run!("cat #{test_file}", dir: test_dir)
    #  |> String.trim
#
    #  assert test_run == test_content
#
    #  File.rm_rf!(test_dir)
    #end
#
    #test "an erroring command errors with run" do
    #  test_run = "localhost"
    #  |> SSH.connect!
    #  |> SSH.run("false")
#
    #  {str, code} = System.cmd("false", [])
#
    #  assert {:ok, str, code} == test_run
    #end
#
    #test "run timeouts work" do
    #  assert {:error, :timeout} = "localhost"
    #  |> SSH.connect!
    #  |> SSH.run("sleep 10", timeout: 100)
    #end
  end
end
