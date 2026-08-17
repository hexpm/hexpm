defmodule HexpmWeb.API.OIDCControllerTest do
  use HexpmWeb.ConnCase, async: false
  import Mox

  alias Hexpm.TrustedPublisherHelpers

  setup :verify_on_exit!

  setup do
    TrustedPublisherHelpers.ensure_oauth_client()
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

    %{package: package}
  end

  test "GET /api/oidc/audience" do
    conn = get(build_conn(), "/api/oidc/audience")
    assert json_response(conn, 200) == %{"audience" => "hexpm"}
  end

  test "POST /api/oidc/mint-token exchanges a valid OIDC token", %{package: package} do
    oidc =
      TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/oidc/mint-token", %{
        "token" => oidc,
        "repository" => "hexpm",
        "package" => package.name
      })

    body = json_response(conn, 200)
    assert is_binary(body["token"])
    assert body["token_type"] == "bearer"
    assert body["expires_in"] > 0
  end

  test "POST /api/oidc/mint-token rejects missing package" do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/oidc/mint-token", %{"token" => "x"})

    body = json_response(conn, 400)
    assert body["error"] == "invalid_request"
  end

  test "POST /api/oidc/mint-token rejects non-matching publisher", %{package: package} do
    oidc =
      TrustedPublisherHelpers.sign_oidc_claims(
        TrustedPublisherHelpers.github_claims(workflow: "nope.yml")
      )

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/oidc/mint-token", %{
        "token" => oidc,
        "package" => package.name
      })

    assert json_response(conn, 403)["error"] == "access_denied"
  end

  test "POST /api/oidc/mint-token rejects replayed tokens", %{package: package} do
    oidc =
      TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    params = %{
      "token" => oidc,
      "package" => package.name
    }

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/oidc/mint-token", params)
    |> json_response(200)

    body =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/oidc/mint-token", params)
      |> json_response(400)

    assert body["error"] == "invalid_grant"
    assert body["error_description"] =~ "already been used"
  end

  test "POST /api/oidc/mint-token returns 404 when feature disabled", %{package: package} do
    previous = Application.get_env(:hexpm, :features)
    Application.put_env(:hexpm, :features, trusted_publishers: false)
    on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

    oidc =
      TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    body =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/oidc/mint-token", %{
        "token" => oidc,
        "package" => package.name
      })
      |> json_response(404)

    assert body["error"] == "not_found"
  end
end
