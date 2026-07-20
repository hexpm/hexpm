defmodule HexpmWeb.Session.TTL do
  # Session flow state (TFA login, pending OAuth signup) lives in the
  # cookie until cookie expiry, so replay protection has to come from
  # timestamps embedded in the values themselves.

  def within?(iso8601, duration) when is_binary(iso8601) do
    case NaiveDateTime.from_iso8601(iso8601) do
      {:ok, at} ->
        expires_at = NaiveDateTime.shift(at, duration)
        NaiveDateTime.compare(NaiveDateTime.utc_now(), expires_at) == :lt

      _ ->
        false
    end
  end

  def within?(_at, _duration), do: false
end
