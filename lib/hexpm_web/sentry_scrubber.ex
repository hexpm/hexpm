defmodule HexpmWeb.SentryScrubber do
  def scrub_body(conn) do
    if sso_path?(conn.request_path) do
      %{}
    else
      Sentry.PlugContext.default_body_scrubber(conn)
    end
  end

  def scrub_url(%{request_path: "/sso/callback"} = conn) do
    conn
    |> Sentry.PlugContext.default_url_scrubber()
    |> URI.parse()
    |> Map.put(:query, nil)
    |> URI.to_string()
  end

  def scrub_url(conn), do: Sentry.PlugContext.default_url_scrubber(conn)

  defp sso_path?(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.member?("sso")
  end
end
