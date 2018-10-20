defmodule HexpmWeb.ConsultFormat do
  def encode(map) when is_map(map) do
    map
    |> Hexpm.Utils.binarify(maps: false)
    |> Enum.map(&[:io_lib.print(&1) | ".\n"])
    |> IO.iodata_to_binary()
  end

  def decode(string) when is_binary(string) do
    string = String.to_charlist(string)

    case :safe_erl_term.string(string) do
      {:ok, tokens, _line} ->
        try do
          terms = :safe_erl_term.terms(tokens)
          result = Enum.into(terms, %{})
          {:ok, result}
        rescue
          FunctionClauseError ->
            {:error, "invalid terms"}

          ArgumentError ->
            {:error, "not in key-value format"}
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
