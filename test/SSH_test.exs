defmodule SSHTest do
  use ExUnit.Case, async: true

  @moduletag :ssh

  describe "when attempting to use run/3" do
    test "can trigger a program to run" do
      test_run =
        "localhost"
        |> SSH.connect!()
        |> SSH.run!("echo foo")
        |> String.trim()

      assert test_run == "foo"
    end

    @tmp_file "/tmp/test_foo"
    @tmp_data "foo"

    test "can issue a run in another directory" do
      File.rm_rf!(@tmp_file)
      File.write!(@tmp_file, @tmp_data)

      test_run =
        "localhost"
        |> SSH.connect!()
        |> SSH.run!("cat #{Path.basename(@tmp_file)}", dir: Path.dirname(@tmp_file))

      assert test_run == @tmp_data
    end

    test "runs can time out" do
      assert {:error, _, :timeout} =
               "localhost"
               |> SSH.connect!()
               |> SSH.run("sleep 10", timeout: 300)
    end
  end
end
