# Librarian

**An Elixir SSH library**

Elixir's SSH offering needs a major revamp.  `:librarian` provides a module,
`SSH`, that is well-typed, and, under the hood, uses Elixir's `Stream` module.

Librarian does not create any worker pools or have any opinions on how you should
manage processes or supervision trees.  Future releases may provide
batteries-included solutions for these concerns, but Librarian will never
instantiate running processes in your BEAM without an explicit command to do so.  
Currently, because librarian uses `Stream` it cannot multiplex ssh channels on a
single BEAM process, but support for those uses cases may be forthcoming.

## Usage

**Warning** the app `:librarian` defines the `SSH` module.  We can't call the
package `:ssh` due to conflicts with the erlang `:ssh` builtin module.

## Supported Platforms

`:librarian` is currently only tested on linux.  MacOSX should in theory work, 
and there are parts that will probably **not** work on Windows.  Any assistance 
getting these platforms up and running would be appreciated.

### For Mix Tasks and releases

If you would like to use Librarian in Mix Tasks or Releases, you should make 
sure that `Application.ensure_all_running(:ssh)` has been called *before* you 
attempt any Librarian commands, or else you may wind up with a race condition, 
since OTP may take a while to get its default `:ssh` package up and running.

## Examples

**NB** all of these commands assume that you have passwordless ssh keys to the 
server "some.other.server", to the user with the same username as the currently 
running BEAM VM.  For help with other uses, consult the documentation.

```elixir
  {:ok, conn} = SSH.connect("some.other.server")
  SSH.run!(conn, "echo hello ssh")  # ==> "hello ssh"
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

For all three of these operations, Librarian provides an ok tuple form or a bang form.  See the documentation for the details on these forms.

Finally, you can use the underlying SSH stream functionality directly, by emitting a stream of values:

```elixir
  "some.other.server"
  |> SSH.connect!
  |> SSH.stream!("some_long_running_process")
  |> Enum.each(SomeModule.some_action/1)
```

Like the `IO.Stream` struct, the `SSH.Stream` struct emitted by `SSH.stream!/2` is both an `Enumerable` and a `Collectable`, so you can use it to accept a datastream to send to the *standard in* of your remote ssh command.

```elixir
  conn = SSH.connect!("some.other.server")
  1..1000
  |> Stream.map(&(inspect(&1) <> "\n"))
  |> Enum.into(SSH.stream!("tee > one_to_one_thousand.txt"))
```

These are the basic use cases.  You can find more information about more advanced use cases at [https://hexdocs.pm/librarian](https://hexdocs.pm/librarian).

## Installation

This package can be installed by adding `librarian` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:librarian, "~> 0.1.6"}
  ]
end
```

documentation can be found here: [https://hexdocs.pm/librarian/SSH.html](https://hexdocs.pm/librarian/SSH.html)

## Testing

Almost all of Librarian's tests are integration tests.  These tests are end-to-end and run against an active, default Linux SSH server.  To properly run these tests, you should have the following:

- The latest version of [OpenSSH](https://openssh.com)
- A default, passwordless `id_rsa.pub` in your `~/.ssh` directory.
  ```
  [ -f ~/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa.pub
  ```
- The default key as an authorized key.
  ```
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  ```

We will be working on setting up alternative testing strategies in the future.
