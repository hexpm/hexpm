defmodule HexpmWeb.Session.JSON do
  # Session cookie serializer with the same semantics as the legacy
  # database store's jsonb column: atom keys become strings and only
  # JSON-representable values survive a roundtrip.

  def encode(term) do
    case Jason.encode(term) do
      {:ok, binary} -> {:ok, binary}
      {:error, _} -> :error
    end
  end

  def decode(binary) do
    case Jason.decode(binary) do
      {:ok, term} -> {:ok, term}
      {:error, _} -> :error
    end
  end
end
