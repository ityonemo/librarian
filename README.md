# Librarian

**An Elixir SSH library**

Elixir's SSH offering needs a major revamp.  `:librarian` provides a module, `SSH`,
that is well-typed, and, under the hood, uses Elixir's `Stream` module.

## Usage

**Warning** the app `:librarian` defines the `SSH` module.  We can't call the 
package `:ssh` due to conflicts with the erlang `:ssh` builtin module.

```elixir
  {:ok, conn} = SSH.connect("localhost")
  SSH.send(conn, "test.sh", "#!/bin/sh\necho hello ssh")
  SSH.run!(conn, "sh ./test.sh")  # ==> "hello ssh"
```

You can also emit a stream of values:
```elixir
  conn = SSH.connect!("some.other.server")
  conn
  |> SSH.stream("some_long_running_process")
  |> Enum.map(&IO.puts/1)
``` 

Like the `IO.Stream` struct, the `SSH.Stream` struct emitted by `SSH.stream/2` is
both an `Enumerable` and a `Collectable`, so you can use it to accept a datastream
to send to the *standard in* of your remote ssh command.

```elixir
  conn = SSH.connect!("some.other.server")
  1..1000
  |> Stream.map(&(inspect(&1) <> "\n"))
  |> SSH.stream("tee > one_to_one_thousand.txt")
```

Note that for most operations, Librarian creates both an ok tuple and a 

## Installation

This package can be installed by adding `librarian` to your list of dependencies in 
`mix.exs`:

```elixir
def deps do
  [
    {:librarian, "~> 0.1.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/librarian](https://hexdocs.pm/librarian).

