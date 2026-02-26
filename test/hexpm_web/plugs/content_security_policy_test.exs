defmodule HexpmWeb.Plugs.ContentSecurityPolicyTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Plugs.ContentSecurityPolicy

  @dsn "https://abc123@o123.ingest.us.sentry.io/456"
  @report_uri "https://o123.ingest.us.sentry.io/api/456/security/?sentry_key=abc123"

  describe "CSP reporting from Sentry DSN" do
    test "adds report-uri and report-to directives when Sentry DSN is configured" do
      Application.put_env(:sentry, :dsn, @dsn)
      on_exit(fn -> Application.delete_env(:sentry, :dsn) end)

      conn =
        build_conn()
        |> ContentSecurityPolicy.call(
          nonces_for: [:script_src],
          directives: %{default_src: ~w('self')}
        )

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "report-uri #{@report_uri}"
      assert csp =~ "report-to csp-endpoint"
    end

    test "adds Report-To header when Sentry DSN is configured" do
      Application.put_env(:sentry, :dsn, @dsn)
      on_exit(fn -> Application.delete_env(:sentry, :dsn) end)

      conn =
        build_conn()
        |> ContentSecurityPolicy.call(
          nonces_for: [:script_src],
          directives: %{default_src: ~w('self')}
        )

      [report_to] = get_resp_header(conn, "report-to")
      decoded = Jason.decode!(report_to)

      assert decoded["group"] == "csp-endpoint"
      assert decoded["max_age"] == 10_886_400
      assert decoded["include_subdomains"] == true
      assert [%{"url" => @report_uri}] = decoded["endpoints"]
    end

    test "adds Reporting-Endpoints header when Sentry DSN is configured" do
      Application.put_env(:sentry, :dsn, @dsn)
      on_exit(fn -> Application.delete_env(:sentry, :dsn) end)

      conn =
        build_conn()
        |> ContentSecurityPolicy.call(
          nonces_for: [:script_src],
          directives: %{default_src: ~w('self')}
        )

      [endpoints] = get_resp_header(conn, "reporting-endpoints")
      assert endpoints == "csp-endpoint=\"#{@report_uri}\""
    end

    test "works without Sentry DSN" do
      Application.delete_env(:sentry, :dsn)

      conn =
        build_conn()
        |> ContentSecurityPolicy.call(
          nonces_for: [:script_src],
          directives: %{default_src: ~w('self')}
        )

      [csp] = get_resp_header(conn, "content-security-policy")
      refute csp =~ "report-uri"
      refute csp =~ "report-to"

      assert get_resp_header(conn, "report-to") == []
      assert get_resp_header(conn, "reporting-endpoints") == []
    end
  end
end
