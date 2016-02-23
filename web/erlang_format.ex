defmodule HexWeb.ErlangFormat do
  def encode_to_iodata!(term) do
    HexWeb.Utils.binarify(term)
    |> :erlang.term_to_binary
  end

  @doc """
  Safely deserialize an erlang formatted string.
  """
  @spec decode(binary) :: term
  def decode("") do
    {:ok, nil}
  end

  def decode(binary) do
    try do
      term = :erlang.binary_to_term(binary, [:safe])
      {:ok, term}
    rescue
      ArgumentError ->
        {:error, "bad binary_to_term"}
    end
  end
end
