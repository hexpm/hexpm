defmodule HexWeb.API.ErlangFormat do
  @doc """
  Encode an elixir term that can be safely deserialized on another machine.
  """
  @spec encode(term) :: binary
  def encode(term) do
    HexWeb.Util.binarify(term)
    |> :erlang.term_to_binary
  end

  @doc """
  Safely deserialize an elixir formatted string.
  """
  @spec decode(binary) :: term
  def decode("") do
    {:ok, nil}
  end

  def decode(binary) do
    try do
      term = :erlang.binary_to_term(binary, [:safe])
      if safe_term?(term) do
        {:ok, term}
      else
        {:error, "unsafe binary_to_term"}
      end
    rescue
      ArgumentError ->
        {:error, "unsafe binary_to_term"}
    end
  end

  # No atoms allowed!
  defp safe_term?(term) when is_number(term), do: true
  defp safe_term?(term) when is_binary(term), do: true
  defp safe_term?(term) when is_boolean(term), do: true
  defp safe_term?(term) when is_list(term), do: Enum.all?(term, &safe_term?/1)
  defp safe_term?(term) when is_tuple(term), do: Enum.all?(Tuple.to_list(term), &safe_term?/1)
  defp safe_term?(term) when is_map(term), do: Enum.all?(term, &safe_term?/1)
  defp safe_term?(_), do: false
end
