defmodule HexpmWeb.SentryScrubber do
  # Paths whose parameters are dropped whole, query and body alike. `Plug.Parsers`
  # runs before `Sentry.PlugContext`, so the request data Sentry receives is
  # `conn.params`, which holds the query parameters as well as the body; a
  # secret in the query of one of these paths is a secret in both.
  #
  # `sso` and `scim` carry authorization codes, state and the identity
  # provider's record of a person. `oauth` carries an API key as
  # `client_secret`, refresh tokens, authorization codes and the token presented
  # for revocation. `invites` carries the invitation token, `password` and
  # `email` the reset and verification keys.
  @secret_paths ["sso", "scim", "oauth", "invites", "password", "email"]

  # Sentry's server-side list
  # (https://docs.sentry.io/security-legal-pii/scrubbing/server-side-scrubbing/),
  # matched as a substring of the key the way that scrubber matches it, rather
  # than the exact match on three names the SDK applies. Then the names hexpm
  # gives its own secrets: `key` for reset and verification keys, `code` for
  # TOTP, recovery and OAuth codes, `state` for OAuth state, `otp` for the
  # `x-hex-otp` header, and `cookie`, which the SDK's header default covers.
  # `return` is a path, and `requires_login` puts the one it interrupted into it
  # query and all, so an invitation token or reset key arrives nested inside its
  # value where no key match reaches it.
  @sensitive ~w(password secret passwd api_key apikey auth credentials mysql_pwd privatekey
                private_key token bearer key code state otp cookie return)

  @scrubbed "*********"

  # The SDK's default masks a value shaped like a card number whatever its key.
  @card_number ~r/^(?:\d[ -]*?){13,16}$/

  def scrub_body(conn) do
    if path?(conn.request_path, @secret_paths) do
      %{}
    else
      scrub_params(conn.params)
    end
  end

  def scrub_url(conn) do
    uri = URI.parse(Plug.Conn.request_url(conn))

    query =
      if path?(conn.request_path, @secret_paths) do
        nil
      else
        scrub_query(uri.query)
      end

    URI.to_string(%{uri | query: query})
  end

  def scrub_headers(conn) do
    Enum.reject(conn.req_headers, fn {name, _value} -> sensitive?(name) end)
  end

  defp scrub_params(%{} = params) when not is_struct(params) do
    Map.new(params, fn {key, value} ->
      if sensitive?(key), do: {key, @scrubbed}, else: {key, scrub_params(value)}
    end)
  end

  defp scrub_params(list) when is_list(list), do: Enum.map(list, &scrub_params/1)
  defp scrub_params(value), do: scrub_value(value)

  defp scrub_query(nil), do: nil

  defp scrub_query(query) do
    query
    |> URI.query_decoder()
    |> Enum.map(fn {key, value} ->
      if sensitive?(key), do: {key, @scrubbed}, else: {key, scrub_value(value)}
    end)
    |> URI.encode_query()
  end

  defp scrub_value(value) when is_binary(value) do
    if value =~ @card_number, do: @scrubbed, else: value
  end

  defp scrub_value(value), do: value

  defp sensitive?(key) when is_binary(key) do
    key = String.downcase(key)
    Enum.any?(@sensitive, &String.contains?(key, &1))
  end

  defp sensitive?(_key), do: false

  defp path?(path, segments) do
    path_segments = String.split(path, "/", trim: true)
    Enum.any?(segments, &(&1 in path_segments))
  end
end
