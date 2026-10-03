defmodule HexpmWeb.SentryScrubberTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias HexpmWeb.SentryScrubber

  test "removes OIDC state and authorization codes from callback diagnostics" do
    conn =
      conn(
        :get,
        "/sso/callback?state=raw-state&code=raw-code&error_description=private-provider-state"
      )

    assert SentryScrubber.scrub_url(conn) == "http://www.example.com/sso/callback"

    assert SentryScrubber.scrub_body(conn) == %{}
  end

  test "removes third-party initiation parameters from diagnostics" do
    for path <- [
          "/sso/acme?iss=https%3A%2F%2Fidp.example&login_hint=private%40example.com&target_link_uri=https%3A%2F%2Fhex.pm%2Fdashboard%2Forgs%2Facme",
          "/sso/org/acme?iss=https%3A%2F%2Fidp.example&login_hint=private%40example.com"
        ] do
      conn = conn(:get, path)
      scrubbed = SentryScrubber.scrub_url(conn)

      refute scrubbed =~ "private"
      refute scrubbed =~ "target_link_uri"
      assert URI.parse(scrubbed).query == nil
      assert SentryScrubber.scrub_body(conn) == %{}
    end
  end

  test "retains ordinary scrubbed request URLs" do
    conn = conn(:get, "/packages?search=ecto")
    assert SentryScrubber.scrub_url(conn) == "http://www.example.com/packages?search=ecto"
  end

  test "removes the API key the token endpoint receives as client_secret" do
    conn =
      conn(:post, "/api/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => "client-id",
        "client_secret" => "raw-api-key"
      })

    assert SentryScrubber.scrub_body(conn) == %{}
  end

  test "removes the credentials the other OAuth endpoints receive" do
    for {path, params} <- [
          {"/api/oauth/token", %{"refresh_token" => "raw-refresh-token"}},
          {"/api/oauth/revoke", %{"token" => "raw-token"}},
          {"/oauth/device/authorize", %{"user_code" => "RAW-CODE"}}
        ] do
      conn = conn(:post, path, params)
      assert SentryScrubber.scrub_body(conn) == %{}
    end
  end

  test "removes reset and verification keys from the query" do
    for path <- [
          "/password/new?username=someone&key=raw-reset-key",
          "/email/verify?username=someone&email=someone%40example.com&key=raw-verification-key"
        ] do
      conn = conn(:get, path)
      scrubbed = SentryScrubber.scrub_url(conn)

      refute scrubbed =~ "raw-"
      assert URI.parse(scrubbed).query == nil
    end
  end

  test "removes configuration and rotation parameters from Sentry data" do
    for path <- [
          "/dashboard/orgs/acme/sso/configure",
          "/dashboard/orgs/acme/sso/rotate"
        ] do
      conn =
        conn(:post, path, %{
          "sso" => %{"client_id" => "client-id", "client_secret" => "raw-secret"}
        })

      assert SentryScrubber.scrub_body(conn) == %{}
    end
  end

  describe "the request Sentry receives" do
    # `Plug.Parsers` runs before `Sentry.PlugContext` on the endpoint, so the
    # request data Sentry sends is `conn.params` with the query merged in. These
    # go through both, the way a request does, rather than calling the
    # scrubbers on a conn that was never parsed.
    @parsers Plug.Parsers.init(
               parsers: [:urlencoded, :json, HexpmWeb.PlugParser],
               pass: ["*/*"],
               json_decoder: JSON
             )

    @context Sentry.PlugContext.init(
               body_scrubber: {SentryScrubber, :scrub_body},
               header_scrubber: {SentryScrubber, :scrub_headers},
               url_scrubber: {SentryScrubber, :scrub_url}
             )

    defp sentry_request(method, path, body \\ nil, headers \\ []) do
      conn =
        case body do
          nil ->
            conn(method, path)

          body ->
            conn(method, path, JSON.encode!(body))
            |> Plug.Conn.put_req_header("content-type", "application/json")
        end

      conn =
        headers
        |> Enum.reduce(conn, fn {name, value}, conn ->
          Plug.Conn.put_req_header(conn, name, value)
        end)
        |> Plug.Parsers.call(@parsers)

      Sentry.PlugContext.call(conn, @context)
      Sentry.Context.get_all().request
    end

    defp refute_leaks(request) do
      refute inspect(request, limit: :infinity) =~ "raw-"
    end

    test "drops a reset key from the request data as well as the URL" do
      refute_leaks(sentry_request(:get, "/password/new?username=someone&key=raw-reset-key"))
    end

    test "drops an invitation token from the request data" do
      refute_leaks(sentry_request(:get, "/invites?token=raw-invitation-token"))
      refute_leaks(sentry_request(:post, "/invites", %{"token" => "raw-invitation-token"}))
    end

    test "masks a return path holding another path's secret" do
      for path <- [
            "/login?return=%2Finvites%3Ftoken%3Draw-invitation-token",
            "/auth/github?return=%2Finvites%3Ftoken%3Draw-invitation-token"
          ] do
        refute_leaks(sentry_request(:get, path))
      end
    end

    test "masks 2FA and recovery codes" do
      for {path, body} <- [
            {"/tfa", %{"code" => "raw-totp"}},
            {"/tfa/recovery", %{"code" => "raw-recovery-code"}},
            {"/sudo", %{"type" => "tfa", "code" => "raw-totp"}},
            {"/sudo/recovery", %{"code" => "raw-recovery-code"}},
            {"/dashboard/security/verify-tfa-code", %{"verification_code" => "raw-totp"}}
          ] do
        refute_leaks(sentry_request(:post, path, body))
      end
    end

    test "masks passwords under names other than password" do
      refute_leaks(
        sentry_request(:post, "/dashboard/security/change-password", %{
          "user" => %{
            "password_current" => "raw-old-password",
            "password" => "raw-new-password",
            "password_confirmation" => "raw-new-password"
          }
        })
      )
    end

    test "masks the code and state GitHub sends back" do
      refute_leaks(sentry_request(:get, "/auth/github/callback?code=raw-code&state=raw-state"))
    end

    test "drops the one-time password header" do
      refute_leaks(
        sentry_request(:post, "/api/packages/x/releases", %{}, [{"x-hex-otp", "raw-otp"}])
      )
    end

    test "keeps the referrer's path but not its query" do
      request =
        sentry_request(:post, "/password/new", %{}, [
          {"referer", "https://hex.pm/password/new?username=someone&key=raw-reset-key#frag"}
        ])

      refute_leaks(request)
      assert request.headers["referer"] == "https://hex.pm/password/new"
    end

    test "keeps ordinary query and body parameters" do
      request = sentry_request(:get, "/packages?search=ecto&sort=downloads")
      assert request.url == "http://www.example.com/packages?search=ecto&sort=downloads"
      assert request.data == %{"search" => "ecto", "sort" => "downloads"}

      request = sentry_request(:post, "/dashboard/profile", %{"user" => %{"full_name" => "Ada"}})
      assert request.data == %{"user" => %{"full_name" => "Ada"}}
    end
  end
end
