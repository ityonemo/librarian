defmodule SSH.SCPState do
  defstruct content: [],
            size: nil,
            file: nil,
            permissions: nil,
            in_file: false

  def stream_reducer(<<?C, ?0, perm::binary-size(3), 32>> <> size_file, state = %{in_file: false}) do
    start_state(state, size_file, perm)
  end
  def stream_reducer(<<?C, 32, ?0, perm::binary-size(3), 32>> <> size_file, state = %{in_file: false}) do
    start_state(state, size_file, perm)
  end
  def stream_reducer(binary, state) when is_binary(binary) do
    %__MODULE__{state | content: [state.content | String.trim(binary, <<0>>)]}
  end

  defp start_state(state, size_file, perm_str) do
    [size_str, file] = size_file
    |> String.trim(<<0>>)
    |> String.split

    size = String.to_integer(size_str)
    perm = String.to_integer(perm_str, 8)

    %__MODULE__{state | size: size, file: file, permissions: perm, in_file: true}
  end

  def timeout_handler(stream) do
    SSH.Stream.send_packet(stream, <<0>>)
  end

end
