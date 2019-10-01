defmodule SSH.ModuleApi do
  @moduledoc """
  API for rolling all of the SSH stream functions into a single module.

  This allows you to organize your stream IO transactions in a consistent
  fashion.  Implementing this behaviour is particularly useful for
  interactive data streams - consider examining `SSH.SCP.Send` for a
  good example of how to implement a data stream that needs to exchange
  data in response to counterparty output.
  """

  @doc """
  initializes your SSH stream.

  A return value of `{:ok, stream}` means that any preconditions for the
  stream have been successfully completed.  You should return the initialized
  accumulator as the second part of the tuple.  A return value of `{:error, any}`
  indicates an error in initialization, and the SSH channel will not be created.
  """
  @callback init(SSH.Stream.t, term) :: {:ok, SSH.Stream.t} | {:error, any}

  @doc """
  responds to binary data coming over the standard out segment of the data
  stream.

  Note you may convert these data to multiple terms, which are then going to
  be marshalled as the stream output of the SSH stream as multiple terms.
  An empty list means that processing these data results in no effect.
  You may also emit `:halt`, which will stop the stream and cause the SSH
  client to send an EOF and close the stream.

  The output of this function is the modified stream.  If you need to
  perform a reduction operation over your stream, the `SSH.Stream` struct
  provides an open-ended `:data` field which you may use to store your
  reducer.

  For interactive data streams, you may find it useful to call the
  `SSH.Stream.send_data/2` or `SSH.Stream.send_eof/1` functions within
  your implementations.
  """
  @callback on_stdout(stream_data::binary, SSH.Stream.t) ::
    {output::[term] | :halt, SSH.Stream.t}

  @doc """
  responds to binary data coming over the standard error segment of the data stream.

  See `c:stdout/2`, execpt with data coming over the standard error subchannel.
  """
  @callback on_stderr(stream_data::binary, SSH.Stream.t) ::
    {output::[term] | :halt, SSH.Stream.t}

  @doc """
  responds to when it takes too long for the other side to respond with data.

  This is most useful for interactive data streams.  By default, if you do
  not implement this function, the `SSH.Stream` module will pick an
  implementation that closes the connection.
  """
  @callback on_timeout(SSH.Stream.t) :: {[], SSH.Stream.t}
end
