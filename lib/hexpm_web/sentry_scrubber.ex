defmodule HexpmWeb.SentryScrubber do
  # Paths whose query string carries a secret. Both loggers on the endpoint
  # record `conn.request_path`, which excludes the query, so keeping these
  # secrets out of the path is what stops them reaching stdout; this is what
  # stops them reaching Sentry. `login` is here because `requires_login` puts
  # the path it interrupted, query and all, into `return`.
  # `scim` carries the identity provider's record of a person, `userName` and
  # `externalId`, in the body and in the filter. `password` and `email` carry
  # the reset and verification keys as `key`, which Sentry's own scrubber keeps
  # because it matches `password`, `passwd` and `secret` exactly.
  @secret_query_paths ["sso", "invites", "login", "scim", "password", "email"]
  # `oauth` bodies carry an API key as `client_secret`, plus refresh tokens,
  # authorization codes and the token presented for revocation. Sentry's
  # exact-match scrubber keeps every one of them.
  @secret_body_paths ["sso", "scim", "oauth"]

  def scrub_body(conn) do
    if path?(conn.request_path, @secret_body_paths) do
      %{}
    else
      Sentry.PlugContext.default_body_scrubber(conn)
    end
  end

  def scrub_url(conn) do
    if path?(conn.request_path, @secret_query_paths) do
      scrub_query(conn)
    else
      Sentry.PlugContext.default_url_scrubber(conn)
    end
  end

  defp scrub_query(conn) do
    conn
    |> Sentry.PlugContext.default_url_scrubber()
    |> URI.parse()
    |> Map.put(:query, nil)
    |> URI.to_string()
  end

  defp path?(path, segments) do
    path_segments = String.split(path, "/", trim: true)
    Enum.any?(segments, &(&1 in path_segments))
  end
end
