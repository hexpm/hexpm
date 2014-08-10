defmodule HexWeb.API.ElixirFormat do
  @doc """
  Encode an elixir term that can be safely deserialized on another machine.
  """
  @spec encode(term) :: String.t
  def encode(term) do
    HexWeb.Util.binarify(term)
    |> inspect(limit: 80, binaries: :as_strings)
  end

  @doc """
  Safely deserialize an elixir formatted string.
  """
  @spec decode(String.t) :: term
  def decode("") do
    {:ok, nil}
  end

  def decode(string) do
    case Code.string_to_quoted(string, existing_atoms_only: true) do
      {:ok, ast} ->
        safe_eval(ast)
      _ ->
        {:error, "malformed elixir"}
    end
  end

  defp safe_eval(ast) do
    if safe_term?(ast) do
      result = Code.eval_quoted(ast)
               |> elem(0)
               |> list_to_map
      {:ok, result}
    else
      {:error, "unsafe elixir"}
    end
  end

  defp safe_term?({func, _, terms}) when func in [:{}, :%{}] and is_list(terms) do
    Enum.all?(terms, &safe_term?/1)
  end

  defp safe_term?(nil), do: true
  defp safe_term?(term) when is_number(term), do: true
  defp safe_term?(term) when is_binary(term), do: true
  defp safe_term?(term) when is_boolean(term), do: true
  defp safe_term?(term) when is_list(term), do: Enum.all?(term, &safe_term?/1)
  defp safe_term?(term) when is_tuple(term), do: Enum.all?(Tuple.to_list(term), &safe_term?/1)
  defp safe_term?(_), do: false

  # can be removed when users are on hex v0.3.2
  # (released 2014-07-05) (requires elixir v0.14.2)
  defp list_to_map(list) when is_list(list) do
    if list == [] or is_tuple(List.first(list)) do
      Enum.into(list, %{}, fn
        {key, list} when is_list(list) -> {key, list_to_map(list)}
        other -> list_to_map(other)
      end)
    else
      Enum.map(list, &list_to_map/1)
    end
  end

  defp list_to_map(other) do
    other
  end
end
