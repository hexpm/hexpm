defmodule Hexpm.Web.ErlangFormat do
  def encode_to_iodata!(term) do
    Hexpm.Utils.binarify(term)
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
    case Hexpm.Utils.safe_binary_to_term(binary, [:safe]) do
      {:ok, term} ->
        {:ok, term}
      :error ->
        {:error, "bad binary_to_term"}
    end
  rescue
    ArgumentError ->
      {:error, "bad binary_to_term"}
  end
end
