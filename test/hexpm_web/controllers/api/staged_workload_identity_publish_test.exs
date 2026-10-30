defmodule HexpmWeb.API.StagedWorkloadIdentityPublishTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Repository.{Package, Release, StagedReleases}
  alias Hexpm.WorkloadIdentityHelpers

  setup :verify_on_exit!

  setup do
    put_feature_flag(:workload_identity, mode: :enabled)
    WorkloadIdentityHelpers.stub_oidc_discovery()
    user = insert(:user_with_tfa)

    package =
      insert(:package,
        package_owners: [build(:package_owner, user: user)],
        meta: build(:package_metadata, description: "Published")
      )

    wi =
      insert(:workload_identity,
        package: package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repositories: [
          %Hexpm.WorkloadIdentities.TrustedRepository{name: "acme/widget", id: "67890"}
        ],
        workflow: "release.yml"
      )

    %{user: user, package: package, wi: wi}
  end

  test "a public workload identity stages, and approval records its claims and the approver",
       ctx do
    token = mint(ctx.package)
    result = publish(ctx, token) |> json_response(201)
    assert result["status"] == "staged"
    assert Repo.get!(Package, ctx.package.id).meta.description == "Published"
    assert Repo.aggregate(Release, :count) == 0
    assert read(token, result["id"]) |> json_response(200) |> Map.fetch!("status") == "staged"

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases/#{result["id"]}")
      |> html_response(200)
      |> LazyHTML.from_document()

    claims = StagedReleases.get(result["id"]).oidc_claims
    assert LazyHTML.text(page) =~ "Source repository"
    assert LazyHTML.text(page) =~ claims["repository"]
    assert LazyHTML.text(page) =~ claims["workflow_ref"]
    assert LazyHTML.text(page) =~ claims["sha"]

    assert page
           |> LazyHTML.query(
             ~s(a[href="https://github.com/#{claims["repository"]}/actions/runs/#{claims["run_id"]}"])
           )
           |> LazyHTML.text() =~ "View workflow run"

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
    |> response(302)

    release = Repo.one!(Release)
    assert release.workload_identity_id == ctx.wi.id
    assert release.publisher_id == nil
    assert release.approved_by_id == ctx.user.id
    assert release.oidc_claims.repository == "acme/widget"
    assert release.oidc_claims.sha
    assert Repo.get!(Package, ctx.package.id).meta.description == "From CI"
  end

  test "a changed or deleted identity can't publish a staged release", ctx do
    result = publish(ctx, mint(ctx.package)) |> json_response(201)
    Repo.update!(Ecto.Changeset.change(ctx.wi, workflow: "other.yml"))

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
    |> response(409)

    assert StagedReleases.get(result["id"])
    Repo.delete!(ctx.wi)

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
    |> response(409)

    assert Repo.aggregate(Release, :count) == 0
  end

  test "public API keys follow the package approval setting", ctx do
    key = insert(:key, user: ctx.user)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)
      |> post(
        "/api/publish",
        create_tar(%{name: ctx.package.name, version: "1.0.0", description: "From key"})
      )

    result = json_response(conn, 201)
    assert result["status"] == "staged"
    assert Repo.aggregate(Release, :count) == 0
  end

  test "a second workload identity can't avoid package approval", ctx do
    second =
      insert(:workload_identity,
        package: ctx.package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repositories: [
          %Hexpm.WorkloadIdentities.TrustedRepository{name: "acme/widget", id: "67890"}
        ],
        workflow: "other.yml"
      )

    oidc =
      WorkloadIdentityHelpers.github_claims(workflow: "other.yml")
      |> WorkloadIdentityHelpers.sign_oidc_claims()

    {:ok, token} =
      Hexpm.WorkloadIdentities.verify_and_mint(oidc,
        repository: "hexpm",
        package: ctx.package.name
      )

    staged = publish(ctx, token) |> json_response(201)
    assert staged["status"] == "staged"
    assert StagedReleases.get(staged["id"]).workload_identity_id == second.id
    assert Repo.aggregate(Release, :count) == 0
  end

  test "an opted-out package permits API-key publishing", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
    key = insert(:key, user: ctx.user)

    result =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)
      |> post(
        "/api/publish",
        create_tar(%{name: ctx.package.name, version: "1.0.0", description: "Direct release"})
      )
      |> json_response(201)

    refute result["status"] == "staged"
    assert Repo.aggregate(Release, :count) == 1
  end

  test "package approval covers API-key docs replacements and blocks automated reverts", ctx do
    release = insert(:release, package: ctx.package, version: "1.0.0")
    key = insert(:key, user: ctx.user)
    {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Replacement docs"}])

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)

    path = "/api/packages/#{ctx.package.name}/releases/1.0.0"
    staged = conn |> post(path <> "/docs", docs) |> json_response(201)
    assert staged["status"] == "staged"
    assert StagedReleases.get(staged["id"]).kind == "docs"
    refute Repo.get!(Release, release.id).has_docs
    conn |> delete(path) |> response(403)
    conn |> delete(path <> "/docs") |> response(403)

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{staged["id"]}/approve", %{
      checksum: staged["approval_checksum"]
    })
    |> response(302)

    assert Repo.get!(Release, release.id).has_docs
  end

  for mode <- [:enabled, :beta] do
    test "new public packages default to approval in #{mode} rollout", ctx do
      put_feature_flag(:workload_identity, mode: unquote(mode), beta_users: [ctx.user.username])
      key = insert(:key, user: ctx.user)
      name = Fake.sequence(:package)

      staged =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key.user_secret)
        |> post(
          "/api/publish",
          create_tar(%{name: name, version: "1.0.0", description: "First release"})
        )
        |> json_response(201)

      assert staged["status"] == "staged"
      refute Repo.get_by(Package, name: name)

      build_conn()
      |> test_login(ctx.user)
      |> post("/dashboard/staged-releases/#{staged["id"]}/approve", %{
        checksum: staged["approval_checksum"]
      })
      |> response(302)

      assert Repo.get_by!(Package, name: name).require_publish_approval
    end
  end

  test "a publish-only key stages and polls through human approval", ctx do
    key =
      insert(:key,
        user: ctx.user,
        permissions: [
          build(:key_permission, domain: "publish", resource: "hexpm/#{ctx.package.name}")
        ]
      )

    staged =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)
      |> post(
        "/api/publish",
        create_tar(%{name: ctx.package.name, version: "1.0.0", description: "Publish-only key"})
      )
      |> json_response(201)

    assert staged["status"] == "staged"

    assert build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("/api/staged-releases/#{staged["id"]}")
           |> json_response(200)
           |> Map.fetch!("status") == "staged"

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{staged["id"]}/approve", %{
      checksum: staged["approval_checksum"]
    })
    |> response(302)

    assert Repo.one!(Release).approved_by_id == ctx.user.id

    assert build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("/api/staged-releases/#{staged["id"]}")
           |> json_response(200)
           |> Map.fetch!("status") == "approved"
  end

  test "API keys publish directly with the Workload Identity flag off", ctx do
    put_feature_flag(:workload_identity, mode: :off)
    result = key_publish(ctx, "1.0.0") |> json_response(201)
    refute result["status"] == "staged"
    assert Repo.aggregate(Release, :count) == 1
  end

  test "beta applies to public packages owned by a listed user", ctx do
    put_feature_flag(:workload_identity,
      mode: :beta,
      beta_users: [ctx.user.username],
      beta_organizations: []
    )

    assert key_publish(ctx, "1.0.0") |> json_response(201) |> Map.fetch!("status") == "staged"

    put_feature_flag(:workload_identity, beta_users: [], beta_organizations: [])

    refute key_publish(ctx, "2.0.0") |> json_response(201) |> Map.get("status") == "staged"
  end

  test "an organization workload identity stages a new private package and its docs", ctx do
    repository =
      insert(:repository, organization: build(:organization, require_publish_approval: true))

    insert(:organization_user,
      organization: repository.organization,
      user: ctx.user,
      role: "write"
    )

    wi =
      insert(:organization_workload_identity,
        organization: repository.organization,
        role: "write",
        covers_private: true,
        repositories: [
          %Hexpm.WorkloadIdentities.TrustedRepository{name: "acme/widget", id: "67890"}
        ],
        workflow: "release.yml"
      )

    oidc = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())
    name = Fake.sequence(:package)

    {:ok, token} =
      Hexpm.WorkloadIdentities.verify_and_mint(oidc, repository: repository.name, package: name)

    path = "/api/repos/#{repository.name}/packages/#{name}/releases"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post(path, create_tar(%{name: name, version: "1.0.0", description: "Private CI"}))

    result = json_response(conn, 201)
    assert result["status"] == "staged"
    refute Repo.get_by(Package, name: name, repository_id: repository.id)
    {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Private docs"}])

    result =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post(path <> "/1.0.0/docs", docs)
      |> json_response(201)

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
    |> response(302)

    package = Repo.get_by!(Package, name: name, repository_id: repository.id)
    release = Repo.get_by!(Release, package_id: package.id)
    assert release.workload_identity_id == wi.id
    assert release.has_docs
  end

  test "an organization workload identity stages public packages without the private policy",
       ctx do
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: ctx.user, role: "write")
    Repo.delete_all(assoc(ctx.package, :package_owners))
    insert(:package_owner, package: ctx.package, user: organization.user, level: "full")
    Repo.delete!(ctx.wi)

    wi =
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        covers_public: true,
        covers_private: false,
        packages: [],
        public_packages: [ctx.package.name],
        repositories: [
          %Hexpm.WorkloadIdentities.TrustedRepository{name: "acme/widget", id: "67890"}
        ],
        workflow: "release.yml"
      )

    result = publish(ctx, mint(ctx.package)) |> json_response(201)
    assert result["status"] == "staged"
    assert StagedReleases.get(result["id"]).workload_identity_id == wi.id

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
    |> response(302)

    assert Repo.one!(Release).workload_identity_id == wi.id
  end

  test "an existing token follows the package approval setting", ctx do
    token = mint(ctx.package)
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
    result = publish(ctx, token) |> json_response(201)
    refute result["status"] == "staged"
    assert Repo.aggregate(Release, :count) == 1
    {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Direct docs"}])

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", "Bearer #{token.access_token}")
    |> post("/api/packages/#{ctx.package.name}/releases/1.0.0/docs", docs)
    |> response(201)

    assert Repo.one!(Release).has_docs
  end

  test "an organization policy overrides a package opt-out" do
    repository =
      insert(:repository, organization: build(:organization, require_publish_approval: true))

    wi =
      insert(:organization_workload_identity,
        organization: repository.organization,
        role: "write",
        workflow: "release.yml"
      )

    package = insert(:package, repository_id: repository.id, require_publish_approval: false)
    audit = %{user: wi, auth_credential: nil}
    assert StagedReleases.required?(repository, package, audit)

    repository = %{
      repository
      | organization: %{repository.organization | require_publish_approval: false}
    }

    refute StagedReleases.required?(repository, package, audit)
  end

  test "the direct transaction rechecks the package policy after authentication", ctx do
    package = Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
    audit = %{user: ctx.wi, auth_credential: nil}
    Repo.update!(Ecto.Changeset.change(package, require_publish_approval: true))

    assert {:error, :staging_required} =
             StagedReleases.check_direct_policy(
               Repo.preload(ctx.package, :repository).repository,
               package,
               audit,
               nil
             )
  end

  test "a private package can require approval without the organization policy" do
    repository = insert(:repository)

    wi =
      insert(:organization_workload_identity,
        organization: repository.organization,
        role: "write",
        workflow: "release.yml"
      )

    assert StagedReleases.required?(repository, nil, %{user: wi, auth_credential: nil})
    refute repository.organization.require_publish_approval
  end

  test "the package policy stages organization-key exchanges and their docs", ctx do
    repository = insert(:repository)

    insert(:organization_user,
      organization: repository.organization,
      user: ctx.user,
      role: "write"
    )

    key = insert(:key, organization: repository.organization, user: nil)

    client =
      insert(:oauth_client,
        allowed_grant_types: ["client_credentials"],
        allowed_scopes: ["api:write"]
      )

    token =
      build_conn()
      |> post("/api/oauth/token", %{
        grant_type: "client_credentials",
        client_id: client.client_id,
        client_secret: key.user_secret,
        scope: "api:write"
      })
      |> json_response(200)
      |> Map.fetch!("access_token")

    name = Fake.sequence(:package)
    path = "/api/repos/#{repository.name}/packages/#{name}/releases"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token}")

    staged =
      conn
      |> post(path, create_tar(%{name: name, version: "1.0.0", description: "Org release"}))
      |> json_response(201)

    assert staged["status"] == "staged"
    {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Private docs"}])
    staged = conn |> post(path <> "/1.0.0/docs", docs) |> json_response(201)

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{staged["id"]}/approve", %{
      checksum: staged["approval_checksum"]
    })
    |> response(302)

    assert Repo.one!(Release).has_docs
    assert conn |> delete(path <> "/1.0.0") |> response(403)
    assert conn |> delete(path <> "/1.0.0/docs") |> response(403)
  end

  test "an organization key stages its first public release for its members to approve",
       ctx do
    repository = insert(:repository)

    insert(:organization_user,
      organization: repository.organization,
      user: ctx.user,
      role: "write"
    )

    key = insert(:key, organization: repository.organization, user: nil)
    name = Fake.sequence(:package)

    result =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)
      |> post(
        "/api/publish",
        create_tar(%{name: name, version: "1.0.0", description: "Org release"})
      )
      |> json_response(201)

    assert result["status"] == "staged"

    assert build_conn()
           |> test_login(ctx.user)
           |> get("/dashboard/staged-releases")
           |> html_response(200) =~ name

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
    |> response(302)

    assert Repo.get_by!(Hexpm.Repository.PackageOwner,
             package_id: Repo.get_by!(Package, name: name).id
           ).user_id == repository.organization.user.id
  end

  defp mint(package) do
    oidc =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.merge(WorkloadIdentityHelpers.github_claims(), %{
          "sha" => String.duplicate("a", 40),
          "ref" => "refs/heads/main",
          "run_id" => "123",
          "run_attempt" => "1"
        })
      )

    {:ok, token} =
      Hexpm.WorkloadIdentities.verify_and_mint(oidc, repository: "hexpm", package: package.name)

    token
  end

  defp publish(ctx, token) do
    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", "Bearer #{token.access_token}")
    |> post(
      "/api/publish",
      create_tar(%{name: ctx.package.name, version: "1.0.0", description: "From CI"})
    )
  end

  defp key_publish(ctx, version) do
    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(ctx.user))
    |> post(
      "/api/publish",
      create_tar(%{name: ctx.package.name, version: version, description: "From a key"})
    )
  end

  defp read(token, id),
    do:
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> get("/api/staged-releases/#{id}")
end
