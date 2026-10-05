defmodule HexpmWeb.API.TrustedPublisherPublishTest do
  use HexpmWeb.ConnCase, async: false
  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{Package, Release}
  alias Hexpm.TrustedPublisherHelpers

  setup :verify_on_exit!

  setup do
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
    assert result["oidc_claims"]["repository"] == "acme/widget"

    assert Hexpm.Repo.get_by!(Package, name: package.name).meta.description == "from CI"

    release = Hexpm.Repo.get_by!(Release, package_id: package.id)
    assert release.trusted_publisher_id == tp.id
    assert release.oidc_claims.workflow_ref =~ "acme/widget/.github/workflows/release.yml"

    log = Hexpm.Repo.get_by!(AuditLog, action: "release.publish")
    assert log.user_id == nil
    assert log.user_data["trusted_publisher_id"] == tp.id
    assert log.oauth_token_id
    assert log.request_id
  end

  test "deleting the trusted publisher keeps the claims snapshot on the release", %{
    package: package,
    trusted_publisher: tp,
    user: user
  } do
    token = mint_token(package)
    conn = publish_release(token, package)
    assert json_response(conn, 201)

    assert {:ok, _} = Hexpm.TrustedPublishers.delete(tp, audit: audit_data(user))

    release = Hexpm.Repo.get_by!(Release, package_id: package.id)
    assert release.trusted_publisher_id == nil
    assert release.oidc_claims.repository == "acme/widget"
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
        |> post("/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
          "assertion" => oidc,
          "scope" => "package:hexpm/#{pkg.name}"
        })

      minted = json_response(mint_conn, 200)
      meta = %{name: pkg.name, version: "1.0.0", description: "from CI"}

      publish_conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{minted["access_token"]}")
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

  describe "organization repository" do
    setup %{user: user} do
      repository = insert(:repository)

      package =
        insert(:package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:trusted_publisher,
        package: package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repository_id: "67890",
        repository: "acme/widget",
        workflow: "release.yml"
      )

      token =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())
        |> Hexpm.TrustedPublishers.verify_and_mint(
          repository: repository.name,
          package: package.name
        )
        |> then(fn {:ok, token} -> token end)

      %{repository: repository, org_package: package, token: token}
    end

    test "minted token can publish a release", %{
      repository: repository,
      org_package: package,
      token: token
    } do
      meta = %{name: package.name, version: "1.0.0", description: "from CI"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> post("/api/repos/#{repository.name}/publish", create_tar(meta))

      assert json_response(conn, 201)
      assert Hexpm.Repo.get_by!(Release, package_id: package.id, version: "1.0.0")
    end

    test "minted token can publish docs", %{
      repository: repository,
      org_package: package,
      token: token,
      user: user
    } do
      insert(:release, package: package, version: "1.0.0", publisher: user)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> post(
          "/api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/docs",
          create_docs_tar([{"index.html", "docs"}])
        )

      assert conn.status == 201
    end

    test "minted token is refused when organization billing is inactive", %{
      repository: repository,
      org_package: package,
      token: token
    } do
      repository.organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Hexpm.Repo.update!()

      meta = %{name: package.name, version: "1.0.0", description: "from CI"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> post("/api/repos/#{repository.name}/publish", create_tar(meta))

      assert conn.status == 403
    end
  end

  describe "organization publisher" do
    setup do
      repository = insert(:repository)
      organization = repository.organization
      package = insert(:package, repository_id: repository.id)

      trusted_publisher =
        insert(:organization_trusted_publisher,
          organization: organization,
          role: "write",
          repository: "acme/widget",
          workflow: "release.yml"
        )

      %{
        repository: repository,
        organization: organization,
        org_package: package,
        org_publisher: trusted_publisher
      }
    end

    defp mint(opts) do
      TrustedPublisherHelpers.github_claims()
      |> TrustedPublisherHelpers.sign_oidc_claims()
      |> Hexpm.TrustedPublishers.verify_and_mint(opts)
      |> then(fn {:ok, token} -> token end)
    end

    defp publish(token, repository, name, version \\ "1.0.0") do
      meta = %{name: name, version: version, description: "from CI"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/repos/#{repository.name}/publish", create_tar(meta))
    end

    test "publishes a release of a package in the repository", %{
      repository: repository,
      org_package: package,
      org_publisher: tp
    } do
      token = mint(repository: repository.name, package: package.name)

      assert json_response(publish(token, repository, package.name), 201)

      release = Hexpm.Repo.get_by!(Release, package_id: package.id)
      assert release.trusted_publisher_id == tp.id
      assert release.publisher_id == nil
    end

    test "creates a package", %{repository: repository, org_publisher: tp} do
      token = mint(repository: repository.name, package: "new_package")

      result = json_response(publish(token, repository, "new_package"), 201)
      assert result["oidc_claims"]["repository"] == "acme/widget"

      package = Hexpm.Repo.get_by!(Package, repository_id: repository.id, name: "new_package")
      assert Hexpm.Repo.preload(package, :package_owners).package_owners == []

      release = Hexpm.Repo.get_by!(Release, package_id: package.id)
      assert release.trusted_publisher_id == tp.id

      log = Hexpm.Repo.get_by!(AuditLog, action: "release.publish")
      assert log.user_data["trusted_publisher_id"] == tp.id
      assert log.params["package"]["name"] == "new_package"
    end

    test "creates a package through the package releases endpoint", %{repository: repository} do
      token = mint(repository: repository.name, package: "new_package")
      meta = %{name: "new_package", version: "1.0.0", description: "from CI"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> post(
          "/api/repos/#{repository.name}/packages/new_package/releases",
          create_tar(meta)
        )

      assert json_response(conn, 201)
      assert Hexpm.Repo.get_by(Package, repository_id: repository.id, name: "new_package")
    end

    test "can't create a package other than the one the token names", %{
      repository: repository
    } do
      token = mint(repository: repository.name, package: "new_package")

      assert json_response(publish(token, repository, "other_package"), 401)
      refute Hexpm.Repo.get_by(Package, repository_id: repository.id, name: "other_package")
    end

    test "is refused for a package the allowlist stops covering", %{
      repository: repository,
      org_package: package,
      org_publisher: tp
    } do
      token = mint(repository: repository.name, package: package.name)

      tp
      |> Ecto.Changeset.change(packages: ["other_package"])
      |> Hexpm.Repo.update!()

      assert json_response(publish(token, repository, package.name), 404)
    end

    test "is refused after the publisher is removed", %{
      repository: repository,
      org_package: package,
      org_publisher: tp,
      user: user
    } do
      token = mint(repository: repository.name, package: package.name)
      assert {:ok, _} = Hexpm.TrustedPublishers.delete(tp, audit: audit_data(user))

      assert json_response(publish(token, repository, package.name), 401)
    end

    test "can't publish into another organization's repository", %{repository: repository} do
      other = insert(:repository)
      token = mint(repository: repository.name, package: "new_package")

      assert json_response(publish(token, other, "new_package"), 401)
      refute Hexpm.Repo.get_by(Package, repository_id: other.id, name: "new_package")
    end

    test "publishes docs", %{repository: repository, org_package: package, user: user} do
      insert(:release, package: package, version: "1.0.0", publisher: user)
      token = mint(repository: repository.name, package: package.name)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> post(
          "/api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/docs",
          create_docs_tar([{"index.html", "docs"}])
        )

      assert conn.status == 201
    end

    test "a repository token can't publish", %{repository: repository, org_package: package} do
      token = mint(repository: repository.name)

      assert json_response(publish(token, repository, package.name), 401)
      assert json_response(publish(token, repository, "new_package"), 401)
    end

    test "a repository token can't call the API", %{repository: repository} do
      token = mint(repository: repository.name)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "repository", resource: repository.name)

      assert conn.status == 403
    end

    test "a read publisher can't publish", %{
      repository: repository,
      organization: organization,
      org_package: package,
      org_publisher: tp
    } do
      Hexpm.Repo.delete!(tp)

      insert(:organization_trusted_publisher,
        organization: organization,
        repository: "acme/widget",
        workflow: "release.yml"
      )

      token = mint(repository: repository.name)
      assert json_response(publish(token, repository, package.name), 401)
    end
  end
end
