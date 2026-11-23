defmodule HexpmWeb.ErlangFormat do
  def encode_to_iodata!(term) do
    term
    |> Hexpm.Utils.binarify()
    |> :erlang.term_to_binary()
  end

  @spec decode(binary) :: term
  def decode("") do
    {:ok, nil}
  end

  def decode(<<131, 80, _rest::binary>>) do
    {:error, "bad binary_to_term"}
  end

  def decode(binary) do
    term = Plug.Crypto.non_executable_binary_to_term(binary, [:safe])

    if struct?(term) do
      {:error, "bad binary_to_term"}
    else
      {:ok, term}
    end
  rescue
    ArgumentError ->
      {:error, "bad binary_to_term"}
  end

  # A decoded map with a :__struct__ key is dispatched to that struct's protocol
  # implementations, so inspecting or enumerating the params runs code chosen
  # by the client.
  defp struct?(map) when is_map(map) do
    Map.has_key?(map, :__struct__) or
      Enum.any?(map, fn {key, value} -> struct?(key) or struct?(value) end)
  end

  defp struct?([head | tail]), do: struct?(head) or struct?(tail)
  defp struct?(tuple) when is_tuple(tuple), do: struct?(Tuple.to_list(tuple))
  defp struct?(_other), do: false
end
