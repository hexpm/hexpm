defmodule HexpmWeb.Session.JSON do
  # Session cookie serializer with the same semantics as the legacy
  # database store's jsonb column: atom keys become strings and only
  # JSON-representable values survive a roundtrip.

  def encode(term) do
    {:ok, Elixir.JSON.encode!(term)}
  rescue
    _ -> :error
  end

  def decode(binary) do
    case Elixir.JSON.decode(binary) do
      {:ok, term} -> {:ok, term}
      {:error, _} -> :error
    end
  end
end
