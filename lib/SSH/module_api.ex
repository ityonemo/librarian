defmodule SSH.ModuleApi do
  @moduledoc """
  API for rolling all of the SSH stream functions into a single module.

  This allows you to organize your interaction plane in a consistent
  fashion.
  """

  @doc """
  initializes your SSH stream.

  A return value of `{:ok, acc}` means that any preconditions for the
  stream have been successfully completed.  You should return the initialized
  accumulator as the second part of the tuple.  A return value of `{:error, any}`
  indicates an error in initialization, and the SSH channel will not be created.
  """
  @callback init(SSH.Stream.t, term) :: {:ok, acc::term} | {:error, any}

  @doc """
  responds to binary data coming over the standard out segment of the data
  stream.  Note you may convert these data to multiple terms, which are then
  going to be marshalled as the stream output of the SSH stream as multiple terms.
  An empty list means that these data will be silent.  You may also emit `:halt`,
  which will stop the stream and cause the SSH client to send an EOF and close the
  stream.
  """
  @callback stdout(stream_data::binary, acc::term) :: {output::[term] | :halt, acc::term}

  @doc """
  responds to binary data coming over the standard error segment of the data stream.

  See `c:stdout/2`, execpt with data coming over the standard error subchannel.
  """
  @callback stderr(stream_data::binary, acc::term) :: {output::[term] | :halt, acc::term}

  @callback packet_timeout(acc::SSH.Stream.t) :: {[], SSH.Stream.t}
end
