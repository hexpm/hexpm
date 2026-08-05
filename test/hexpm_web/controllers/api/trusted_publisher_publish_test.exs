defmodule HexpmWeb.API.TrustedPublisherPublishTest do
  use HexpmWeb.ConnCase, async: false
  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{Package, Release}
  alias Hexpm.TrustedPublisherHelpers

  setup :verify_on_exit!

  setup do
    TrustedPublisherHelpers.ensure_oauth_client()
    TrustedPublisherHelpers.stub_oidc_discovery()

    user = insert(:user)

    package =
      insert(
        :package,
        package_owners: [build(:package_owner, user: user)],
        meta: build(:package_metadata, description: "original")
      )

    trusted_publisher =
      insert(:trusted_publisher,
        package: package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repository_id: "67890",
        repository: "acme/widget",
        workflow: "release.yml"
      )

    other =
      insert(
        :package,
        package_owners: [build(:package_owner, user: user)],
        meta: build(:package_metadata, description: "other")
      )

    %{package: package, other: other, user: user, trusted_publisher: trusted_publisher}
  end

  defp mint_token(package) do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    assert {:ok, token} =
             Hexpm.TrustedPublishers.verify_and_mint(oidc,
               repository: "hexpm",
               package: package.name
             )

    token
  end

  defp publish_release(token, package, version \\ "1.0.0") do
    meta = %{name: package.name, version: version, description: "from CI"}

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", "Bearer #{token.access_token}")
    |> post("/api/publish", create_tar(meta))
  end

  test "minted token can publish a new release for its package", %{
    package: package,
    trusted_publisher: tp
  } do
    token = mint_token(package)
    conn = publish_release(token, package)

    result = json_response(conn, 201)
    assert result["url"] =~ "api/packages/#{package.name}/releases/1.0.0"
    assert is_nil(result["publisher"])

    assert Hexpm.Repo.get_by!(Package, name: package.name).meta.description == "from CI"

    log = Hexpm.Repo.get_by!(AuditLog, action: "release.publish")
    assert log.user_id == nil
    assert log.user_data["trusted_publisher_id"] == tp.id
  end

  test "one repository config publishes several packages", %{
    package: package,
    other: other,
    trusted_publisher: tp
  } do
    insert(:trusted_publisher,
      package: other,
      repository_owner: tp.repository_owner,
      repository_owner_id: tp.repository_owner_id,
      repository_id: tp.repository_id,
      repository: tp.repository,
      workflow: tp.workflow
    )

    for pkg <- [package, other] do
      oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      mint_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/oidc/mint-token", %{"token" => oidc, "package" => pkg.name})

      minted = json_response(mint_conn, 200)
      meta = %{name: pkg.name, version: "1.0.0", description: "from CI"}

      publish_conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{minted["token"]}")
        |> post("/api/publish", create_tar(meta))

      result = json_response(publish_conn, 201)
      assert result["url"] =~ "api/packages/#{pkg.name}/releases/1.0.0"
    end
  end

  test "minted token cannot publish a different package", %{package: package, other: other} do
    token = mint_token(package)
    meta = %{name: other.name, version: "1.0.0", description: "nope"}

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/publish", create_tar(meta))

    assert json_response(conn, 401)["message"] =~ "not authorized"
  end

  test "minted token cannot create a brand-new package", %{package: package} do
    token = mint_token(package)
    meta = %{name: Fake.sequence(:package), version: "1.0.0", description: "new"}

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/publish", create_tar(meta))

    assert conn.status in [401, 403]
  end

  test "minted token cannot manage owners", %{package: package, user: user} do
    token = mint_token(package)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/packages/#{package.name}/owners/#{user.username}")

    assert conn.status in [401, 403, 404]
  end

  test "minted token cannot manage trusted publishers", %{package: package} do
    token = mint_token(package)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/packages/#{package.name}/trusted_publishers", %{
        "provider" => "github",
        "repository_owner" => "acme",
        "github_repository" => "other",
        "workflow" => "ci.yml"
      })

    assert conn.status in [401, 403]
  end

  test "minted token can publish docs for its package", %{package: package, user: user} do
    insert(:release, package: package, version: "1.0.0", publisher: user)
    token = mint_token(package)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post(
        "/api/packages/#{package.name}/releases/1.0.0/docs",
        create_docs_tar([{"index.html", "docs"}])
      )

    assert conn.status == 201
    assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "1.0.0").has_docs
  end

  test "minted token cannot delete a release", %{package: package, user: user} do
    insert(:release, package: package, version: "1.0.0", publisher: user)
    token = mint_token(package)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> delete("/api/packages/#{package.name}/releases/1.0.0")

    assert conn.status in [401, 403]
    assert Hexpm.Repo.get_by(Release, package_id: package.id)
  end

  test "minted token cannot retire a release", %{package: package, user: user} do
    insert(:release, package: package, version: "1.0.0", publisher: user)
    token = mint_token(package)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/packages/#{package.name}/releases/1.0.0/retire", %{
        "reason" => "security",
        "message" => "test"
      })

    assert conn.status in [401, 403]
  end

  test "minted token cannot delete docs", %{package: package, user: user} do
    insert(:release, package: package, version: "1.0.0", publisher: user, has_docs: true)
    token = mint_token(package)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> delete("/api/packages/#{package.name}/releases/1.0.0/docs")

    assert conn.status in [401, 403]
  end

  test "deleting the trusted publisher invalidates minted tokens", %{
    package: package,
    trusted_publisher: tp,
    user: user
  } do
    token = mint_token(package)
    assert {:ok, _} = Hexpm.TrustedPublishers.delete(tp, audit: audit_data(user))

    conn = publish_release(token, package)
    assert conn.status in [401, 403]
  end
end
