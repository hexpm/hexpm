defmodule HexpmWeb.API.OAuthControllerTrustedPublisherTest do
  use HexpmWeb.ConnCase, async: false
  import Mox

  alias Hexpm.TrustedPublisherHelpers

  @grant_type "urn:ietf:params:oauth:grant-type:jwt-bearer"

  setup :verify_on_exit!

  setup do
    client = TrustedPublisherHelpers.ensure_oauth_client()
    TrustedPublisherHelpers.stub_oidc_discovery()

    user = insert(:user)

    package =
      insert(:package,
        package_owners: [build(:package_owner, user: user, level: "full")]
      )

    insert(:trusted_publisher,
      package: package,
      repository_owner: "acme",
      repository_owner_id: "12345",
      repository_id: "67890",
      repository: "acme/widget",
      workflow: "release.yml"
    )

    %{package: package, client: client}
  end

  defp mint_params(client, assertion, scope) do
    %{
      "grant_type" => @grant_type,
      "client_id" => client.client_id,
      "assertion" => assertion,
      "scope" => scope
    }
  end

  test "exchanges a valid OIDC token for a Hex access token", %{package: package, client: client} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(client, oidc, "package:hexpm/#{package.name}"))

    body = json_response(conn, 200)
    assert is_binary(body["access_token"])
    assert body["token_type"] == "bearer"
    assert body["expires_in"] > 0
    assert body["scope"] == "package:hexpm/#{package.name}"
    refute Map.has_key?(body, "refresh_token")
  end

  test "rejects a missing assertion", %{package: package, client: client} do
    conn =
      build_conn()
      |> post("/api/oauth/token", %{
        "grant_type" => @grant_type,
        "client_id" => client.client_id,
        "scope" => "package:hexpm/#{package.name}"
      })

    body = json_response(conn, 400)
    assert body["error"] == "invalid_request"
  end

  test "rejects a scope that does not name exactly one package", %{client: client} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(client, oidc, "api"))

    body = json_response(conn, 400)
    assert body["error"] == "invalid_scope"
  end

  test "rejects a missing client_id", %{package: package} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> post("/api/oauth/token", %{
        "grant_type" => @grant_type,
        "assertion" => oidc,
        "scope" => "package:hexpm/#{package.name}"
      })

    body = json_response(conn, 401)
    assert body["error"] == "invalid_client"
  end

  test "rejects a client that is not allowed to use this grant", %{package: package} do
    other_client =
      insert(:oauth_client,
        client_type: "public",
        allowed_grant_types: ["client_credentials"],
        allowed_scopes: ["api"]
      )

    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> post(
        "/api/oauth/token",
        mint_params(other_client, oidc, "package:hexpm/#{package.name}")
      )

    body = json_response(conn, 400)
    assert body["error"] == "unauthorized_client"
  end

  test "rejects non-matching publisher", %{package: package, client: client} do
    oidc =
      TrustedPublisherHelpers.sign_oidc_claims(
        TrustedPublisherHelpers.github_claims(workflow: "nope.yml")
      )

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(client, oidc, "package:hexpm/#{package.name}"))

    assert json_response(conn, 403)["error"] == "access_denied"
  end

  test "rejects replayed tokens", %{package: package, client: client} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
    params = mint_params(client, oidc, "package:hexpm/#{package.name}")

    build_conn()
    |> post("/api/oauth/token", params)
    |> json_response(200)

    body =
      build_conn()
      |> post("/api/oauth/token", params)
      |> json_response(400)

    assert body["error"] == "invalid_grant"
    assert body["error_description"] =~ "already been used"
  end

  test "returns unsupported_grant_type when the feature is disabled", %{
    package: package,
    client: client
  } do
    previous = Application.get_env(:hexpm, :features)
    Application.put_env(:hexpm, :features, trusted_publishers: false)
    on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    body =
      build_conn()
      |> post("/api/oauth/token", mint_params(client, oidc, "package:hexpm/#{package.name}"))
      |> json_response(400)

    assert body["error"] == "unsupported_grant_type"
  end
end
