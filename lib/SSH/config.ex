defmodule SSH.Config do
  @moduledoc """
  handles parsing of SSH configuration files.
  """

  @spec parse(String.t) :: %{optional(String.t) => map}

  def parse(config_file) do
    config_file
    |> String.split("\n")
    |> Enum.reduce({[], nil, nil}, &parse_reducer/2)
    |> complete
  end

  @typep parse_intermediate :: {[{String.t, keyword}], String.t | nil, keyword | nil}

  @spec parse_reducer(String.t, parse_intermediate) :: parse_intermediate
  defp parse_reducer("Host " <> hostname, {kw_so_far, nil, nil}) do
    {kw_so_far, hostname, []}
  end
  defp parse_reducer("Host " <> hostname, {kw_so_far, this_name, this_kw}) do
    {kw_so_far ++ [{this_name, this_kw}], String.trim(hostname), []}
  end
  defp parse_reducer(_other, {_, nil, nil}), do: raise "error parsing ssh config file, must begin with a Host statement"
  defp parse_reducer(other, acc = {kw_so_far, this_name, this_map}) do
    other
    |> String.trim
    |> String.split(~r/\s/, parts: 2)
    |> case do
      [string_key, value] ->
        atom_key = string_key |> Macro.underscore |> String.to_atom
        {kw_so_far, this_name, this_map ++ [{atom_key, value}]}
      [""] ->
        acc
      [string] -> raise "error parsing ssh config: stray config #{string}"
    end
  end

  @spec complete(parse_intermediate) :: %{optional(String.t) => keyword}
  defp complete({_, nil, nil}), do: %{}
  defp complete({kw_so_far, this_name, this_kw}) do
    kw_so_far
    |> Kernel.++([{this_name, this_kw}])
    |> Enum.map(fn
      {host, kw} ->
        keymap = kw |> Enum.map(&adjust/1) |> Enum.into(%{})
        {host, keymap} end)
    |> Enum.into(%{})
  end

  @boolean_keys [:hash_based_authentication, :strict_host_key_checking]
  @second_keys [:connect_timeout]

  defp adjust({key, v}) when key in @second_keys do
    {key, String.to_integer(v) * 1000}
  end
  defp adjust({key, v}) when key in @boolean_keys do
    {key, boolean(v)}
  end
  defp adjust(any), do: any

  defp boolean("yes"), do: true
  defp boolean("no"), do: false

end
