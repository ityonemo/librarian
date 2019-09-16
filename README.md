# Librarian

**An Elixir SSH library**

Elixir's SSH offering needs a major revamp.  `:librarian` provides a module,
`SSH`, that is well-typed, and, under the hood, uses Elixir's `Stream` module.

## Usage

**Warning** the app `:librarian` defines the `SSH` module.  We can't call the
package `:ssh` due to conflicts with the erlang `:ssh` builtin module.

```elixir
  {:ok, conn} = SSH.connect("localhost")
  SSH.send(conn, "test.sh", "#!/bin/sh\necho hello ssh")
  SSH.run!(conn, "sh ./test.sh")  # ==> "hello ssh"
```

Librarian provides two `scp`-related commands, fetch and send, which let you fetch or send individual files.

```elixir
  remote_file_binary_content = "some.other.server"
  |> SSH.connect!
  |> SSH.fetch!("remote_file.txt")

  "some.other.server"
  |> SSH.connect!
  |> SSH.send!("foo bar", "remote_foo_bar.txt")
```

Finally, you can use the underlying SSH stream functionality directly, by emitting a stream of values:

```elixir
  "some.other.server"
  |> SSH.connect!
  |> SSH.stream("some_long_running_process")
  |> Enum.each(SomeModule.some_action/1)
```

Like the `IO.Stream` struct, the `SSH.Stream` struct emitted by `SSH.stream/2` is
both an `Enumerable` and a `Collectable`, so you can use it to accept a datastream
to send to the *standard in* of your remote ssh command.

```elixir
  conn = SSH.connect!("some.other.server")
  1..1000
  |> Stream.map(&(inspect(&1) <> "\n"))
  |> Enum.into(SSH.stream("tee > one_to_one_thousand.txt"))
```

These are the basic use cases.  You can find more information about more advanced use cases at [https://hexdocs.pm/librarian](https://hexdocs.pm/librarian).


## Installation

This package can be installed by adding `librarian` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:librarian, "~> 0.1.0"}
  ]
end
```


