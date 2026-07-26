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

  test "removes third-party initiation and confirmation parameters from diagnostics" do
    for path <- [
          "/sso/acme?iss=https%3A%2F%2Fidp.example&login_hint=private%40example.com&target_link_uri=https%3A%2F%2Fhex.pm%2Fdashboard%2Forgs%2Facme",
          "/sso/confirm?code=ABCDEFG234",
          "/sso/discover?email=private%40example.com"
        ] do
      conn = conn(:get, path)
      scrubbed = SentryScrubber.scrub_url(conn)

      refute scrubbed =~ "private"
      refute scrubbed =~ "ABCDEFG234"
      refute scrubbed =~ "target_link_uri"
      assert URI.parse(scrubbed).query == nil
      assert SentryScrubber.scrub_body(conn) == %{}
    end
  end

  test "retains ordinary scrubbed request URLs" do
    conn = conn(:get, "/packages?search=ecto")
    assert SentryScrubber.scrub_url(conn) == "http://www.example.com/packages?search=ecto"
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
end
