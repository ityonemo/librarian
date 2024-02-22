defmodule SSHTest.IdentityTest do
  use ExUnit.Case, async: true

  @moduletag :ssh

  @tmp_identity_file Path.join("/tmp/", Enum.take_random(?a..?z, 8))

  describe "when connecting" do
    test "you can supply an identity file" do
      # copy the id_rsa file to the temporary identity file.
      "~/.ssh/id_rsa"
      |> Path.expand()
      |> File.cp!(@tmp_identity_file)

      # next, attempt to log in and run an ssh command.
      test_run =
        "localhost"
        |> SSH.connect!(identity: @tmp_identity_file)
        |> SSH.run!("echo foo")
        |> String.trim()

      assert test_run == "foo"
    after
      File.rm_rf!(@tmp_identity_file)
    end

    test "you can supply an identity file (unexpanded path)" do
      # next, attempt to log in and run an ssh command.
      test_run =
        "localhost"
        |> SSH.connect!(identity: "~/.ssh/id_rsa")
        |> SSH.run!("echo foo")
        |> String.trim()

      assert test_run == "foo"
    end

    test "you can supply an private key string" do
      private_key =
        "~/.ssh/id_rsa"
        |> Path.expand()
        |> File.read!()

      # next, attempt to log in and run an ssh command.
      test_run =
        "localhost"
        |> SSH.connect!(identity: private_key)
        |> SSH.run!("echo foo")
        |> String.trim()

      assert test_run == "foo"
    end
  end
end
