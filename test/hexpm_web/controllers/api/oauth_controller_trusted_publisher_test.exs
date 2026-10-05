defmodule HexpmWeb.API.OAuthControllerTrustedPublisherTest do
  use HexpmWeb.ConnCase, async: false
  import Mox

  alias Hexpm.TrustedPublisherHelpers

  @grant_type "urn:ietf:params:oauth:grant-type:jwt-bearer"

  setup :verify_on_exit!

  setup do
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

  defp mint_params(assertion, scope) do
    %{
      "grant_type" => @grant_type,
      "assertion" => assertion,
      "scope" => scope
    }
  end

  test "exchanges a valid OIDC token for a Hex access token", %{package: package} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(oidc, "package:hexpm/#{package.name}"))

    body = json_response(conn, 200)
    assert is_binary(body["access_token"])
    assert body["token_type"] == "bearer"
    assert body["expires_in"] > 0
    assert body["scope"] == "package:hexpm/#{package.name}"
    refute Map.has_key?(body, "refresh_token")
  end

  describe "revoke" do
    setup %{package: package} do
      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      %{"access_token" => access_token} =
        build_conn()
        |> post("/api/oauth/token", mint_params(oidc, "package:hexpm/#{package.name}"))
        |> json_response(200)

      %{access_token: access_token}
    end

    test "revokes the token without a client_id", %{access_token: access_token} do
      conn = post(build_conn(), "/api/oauth/revoke", %{"token" => access_token})

      assert response(conn, 200) == ""

      assert {:ok, token} =
               Hexpm.OAuth.Tokens.lookup(access_token, :access, validate: false, preload: [])

      assert Hexpm.OAuth.Tokens.revoked?(token)
    end
  end

  test "rejects a missing assertion", %{package: package} do
    conn =
      build_conn()
      |> post("/api/oauth/token", %{
        "grant_type" => @grant_type,
        "scope" => "package:hexpm/#{package.name}"
      })

    body = json_response(conn, 400)
    assert body["error"] == "invalid_request"
  end

  test "rejects a scope that does not name exactly one package", _context do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(oidc, "api"))

    body = json_response(conn, 400)
    assert body["error"] == "invalid_scope"
  end

  describe "rate limit" do
    setup do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
      on_exit(fn -> PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage) end)
    end

    test "does not limit tokens that fail verification", %{package: package} do
      scope = "package:hexpm/#{package.name}"

      for _ <- 1..40 do
        conn = post(build_conn(), "/api/oauth/token", mint_params("not-a-jwt", scope))
        assert json_response(conn, 400)["error"] == "invalid_grant"
      end

      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
      conn = post(build_conn(), "/api/oauth/token", mint_params(oidc, scope))
      assert json_response(conn, 200)["access_token"]
    end

    test "limits verified failures per repository", %{package: package} do
      scope = "package:hexpm/#{package.name}"

      mint = fn claims ->
        oidc =
          TrustedPublisherHelpers.github_claims()
          |> Map.merge(claims)
          |> TrustedPublisherHelpers.sign_oidc_claims()

        post(build_conn(), "/api/oauth/token", mint_params(oidc, scope))
      end

      wrong_workflow = %{
        "workflow_ref" => "acme/widget/.github/workflows/other.yml@refs/heads/main"
      }

      align_to_throttle_bucket(15 * 60_000)

      for _ <- 1..30 do
        assert json_response(mint.(wrong_workflow), 403)["error"] == "access_denied"
      end

      assert json_response(mint.(wrong_workflow), 429)["error"] == "slow_down"
      assert json_response(mint.(%{}), 429)["error"] == "slow_down"

      other_repository = Map.put(wrong_workflow, "repository_id", "99999")
      assert json_response(mint.(other_repository), 403)["error"] == "access_denied"
    end

    test "rejected events and replayed tokens do not count", %{package: package} do
      scope = "package:hexpm/#{package.name}"

      align_to_throttle_bucket(15 * 60_000)

      for event <- List.duplicate("pull_request_target", 20) ++ List.duplicate("workflow_run", 20) do
        oidc =
          TrustedPublisherHelpers.github_claims()
          |> Map.put("event_name", event)
          |> TrustedPublisherHelpers.sign_oidc_claims()

        conn = post(build_conn(), "/api/oauth/token", mint_params(oidc, scope))
        assert json_response(conn, 400)["error"] == "invalid_grant"
      end

      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
      params = mint_params(oidc, scope)
      assert json_response(post(build_conn(), "/api/oauth/token", params), 200)["access_token"]

      for _ <- 1..35 do
        conn = post(build_conn(), "/api/oauth/token", params)
        assert json_response(conn, 400)["error_description"] =~ "already been used"
      end

      fresh = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
      conn = post(build_conn(), "/api/oauth/token", mint_params(fresh, scope))
      assert json_response(conn, 200)["access_token"]
    end

    test "successful mints do not count", %{package: package} do
      scope = "package:hexpm/#{package.name}"

      for _ <- 1..29,
          do: HexpmWeb.Plugs.Attack.trusted_publisher_mint_throttle({:github_repository, "67890"})

      for _ <- 1..2 do
        oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
        conn = post(build_conn(), "/api/oauth/token", mint_params(oidc, scope))
        assert json_response(conn, 200)["access_token"]
      end
    end
  end

  test "rejects tokens from pull_request_target workflows", %{package: package} do
    oidc =
      TrustedPublisherHelpers.github_claims()
      |> Map.put("event_name", "pull_request_target")
      |> TrustedPublisherHelpers.sign_oidc_claims()

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(oidc, "package:hexpm/#{package.name}"))

    body = json_response(conn, 400)
    assert body["error"] == "invalid_grant"
    assert body["error_description"] =~ "pull_request_target"
  end

  test "rejects non-matching publisher", %{package: package} do
    oidc =
      TrustedPublisherHelpers.sign_oidc_claims(
        TrustedPublisherHelpers.github_claims(workflow: "nope.yml")
      )

    conn =
      build_conn()
      |> post("/api/oauth/token", mint_params(oidc, "package:hexpm/#{package.name}"))

    assert json_response(conn, 403)["error"] == "access_denied"
  end

  test "rejects replayed tokens", %{package: package} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
    params = mint_params(oidc, "package:hexpm/#{package.name}")

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
    package: package
  } do
    previous = Application.get_env(:hexpm, :features)
    Application.put_env(:hexpm, :features, trusted_publishers: false)
    on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    body =
      build_conn()
      |> post("/api/oauth/token", mint_params(oidc, "package:hexpm/#{package.name}"))
      |> json_response(400)

    assert body["error"] == "unsupported_grant_type"
  end

  test "rejects tokens from workflow_run workflows", %{package: package} do
    oidc =
      TrustedPublisherHelpers.github_claims()
      |> Map.put("event_name", "workflow_run")
      |> TrustedPublisherHelpers.sign_oidc_claims()

    body =
      build_conn()
      |> post("/api/oauth/token", mint_params(oidc, "package:hexpm/#{package.name}"))
      |> json_response(400)

    assert body["error"] == "invalid_grant"
    assert body["error_description"] =~ "workflow_run"
  end

  describe "repository scope" do
    setup do
      repository = insert(:repository)

      insert(:organization_trusted_publisher,
        organization: repository.organization,
        repository: "acme/widget"
      )

      %{repository: repository}
    end

    test "exchanges an OIDC token for a repository token", %{repository: repository} do
      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      body =
        build_conn()
        |> post("/api/oauth/token", mint_params(oidc, "repository:#{repository.name}"))
        |> json_response(200)

      assert body["scope"] == "repository:#{repository.name}"
      assert body["expires_in"] in 899..900
      refute Map.has_key?(body, "refresh_token")
    end

    test "rejects an empty repository", _context do
      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      body =
        build_conn()
        |> post("/api/oauth/token", mint_params(oidc, "repository:"))
        |> json_response(400)

      assert body["error"] == "invalid_scope"
    end

    test "rejects a repository and a package scope together", %{
      repository: repository,
      package: package
    } do
      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
      scope = "repository:#{repository.name} package:hexpm/#{package.name}"

      body =
        build_conn()
        |> post("/api/oauth/token", mint_params(oidc, scope))
        |> json_response(400)

      assert body["error"] == "invalid_scope"
    end

    test "answers an unknown organization like no matching publisher", _context do
      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      body =
        build_conn()
        |> post("/api/oauth/token", mint_params(oidc, "repository:missing"))
        |> json_response(403)

      assert body["error"] == "access_denied"
      assert body["error_description"] == "No matching trusted publisher"
    end

    test "names inactive billing after a match", %{repository: repository} do
      repository.organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Hexpm.Repo.update!()

      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      body =
        build_conn()
        |> post("/api/oauth/token", mint_params(oidc, "repository:#{repository.name}"))
        |> json_response(403)

      assert body["error"] == "access_denied"
      assert body["error_description"] =~ "no active billing subscription"
    end
  end
end
