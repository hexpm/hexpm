# TODO: Revisit for Elixir 1.3, which will be adding native DateTime support

if Code.ensure_loaded?(Poison) and Code.ensure_loaded?(Ecto) do
  # This causes a warning because Ecto has already defined this Encoder. Overriding here
  # because Ecto 2 removed the timezone portion of the iso8601 date string. This caused a
  # regression in the API.
  defimpl Poison.Encoder, for: Ecto.DateTime do
    def encode(dt, _opts), do: <<?", (@for.to_iso8601(dt) <> "Z")::binary, ?">>
  end
end
