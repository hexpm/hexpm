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
