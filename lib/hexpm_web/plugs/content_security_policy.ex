defmodule HexpmWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Wrapper around PlugContentSecurityPolicy that adds Sentry CSP reporting.

  Parses the Sentry DSN at runtime to construct the report-uri endpoint.
  DSN format: https://PUBLIC_KEY@INGEST_DOMAIN/PROJECT_ID
  Report URI: https://INGEST_DOMAIN/api/PROJECT_ID/security/?sentry_key=PUBLIC_KEY
  """

  import Plug.Conn

  @behaviour Plug

  @report_group "csp-endpoint"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    case get_report_uri() do
      {:ok, report_uri} ->
        conn
        |> add_reporting_headers(report_uri)
        |> call_csp_plug(opts, report_uri)

      :error ->
        call_csp_plug(conn, opts, nil)
    end
  end

  defp call_csp_plug(conn, opts, report_uri) do
    opts =
      if report_uri do
        directives =
          opts[:directives]
          |> Map.put(:report_uri, [report_uri])
          |> Map.put(:report_to, [@report_group])

        Keyword.put(opts, :directives, directives)
      else
        opts
      end

    PlugContentSecurityPolicy.call(conn, PlugContentSecurityPolicy.init(opts))
  end

  defp add_reporting_headers(conn, report_uri) do
    report_to =
      Jason.encode!(%{
        "group" => @report_group,
        "max_age" => 10_886_400,
        "endpoints" => [%{"url" => report_uri}],
        "include_subdomains" => true
      })

    conn
    |> put_resp_header("report-to", report_to)
    |> put_resp_header("reporting-endpoints", "#{@report_group}=\"#{report_uri}\"")
  end

  defp get_report_uri do
    with {:ok, dsn} <- Application.fetch_env(:sentry, :dsn),
         {:ok, report_uri} <- parse_sentry_dsn(dsn) do
      {:ok, report_uri}
    end
  end

  defp parse_sentry_dsn(dsn) do
    with %URI{scheme: scheme, host: host, path: "/" <> project_id, userinfo: public_key}
         when scheme in ["http", "https"] and is_binary(public_key) <- URI.parse(dsn) do
      {:ok, "#{scheme}://#{host}/api/#{project_id}/security/?sentry_key=#{public_key}"}
    else
      _ -> :error
    end
  end
end
