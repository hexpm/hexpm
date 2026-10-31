defmodule HexpmWeb.API.EmergencyPublishingTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Repository.{Package, Release, StagedReleases}
  alias Hexpm.WorkloadIdentityHelpers

  setup :verify_on_exit!

  setup do
    app_env(:hexpm, :force_publish_approval, true)
    put_feature_flag(:workload_identity, mode: :off)
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

  test "the API key page lists packages protected by emergency mode", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
    html = build_conn() |> test_login(ctx.user) |> get("/dashboard/keys") |> html_response(200)
    notice = html |> LazyHTML.from_document() |> LazyHTML.query("#publish-approval-packages")
    assert LazyHTML.text(notice) =~ ctx.package.name
    assert LazyHTML.text(notice) =~ "Required by emergency publishing mode"
    refute LazyHTML.text(notice) =~ "Required by organization policy"
  end

  test "the override stages public API keys even with rollout off and permits first-package approval",
       ctx do
    key = insert(:key, user: ctx.user)
    name = Fake.sequence(:package)

    result =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)
      |> post(
        "/api/publish",
        create_tar(%{name: name, version: "1.0.0", description: "First release"})
      )
      |> json_response(201)

    assert result["status"] == "staged"
    refute Repo.get_by(Package, name: name)

    assert build_conn()
           |> test_login(ctx.user)
           |> get("/dashboard/staged-releases")
           |> html_response(200) =~ name

    outsider = insert(:user_with_tfa)

    build_conn()
    |> test_login(outsider)
    |> get("/dashboard/staged-releases/#{result["id"]}")
    |> response(404)

    assert build_conn()
           |> test_login(ctx.user)
           |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
             checksum: result["approval_checksum"]
           })
           |> redirected_to() == "/dashboard/staged-releases"

    assert Repo.get_by!(Package, name: name).id == Repo.one!(Release).package_id
  end

  test "the override ignores a package's opt-out and beta lists", ctx do
    put_feature_flag(:workload_identity, mode: :enabled)
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))

    assert publish(ctx, mint(ctx.package)) |> json_response(201) |> Map.fetch!("status") ==
             "staged"

    put_feature_flag(:workload_identity, mode: :beta, beta_users: [], beta_organizations: [])

    assert build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(ctx.user))
           |> post(
             "/api/publish",
             create_tar(%{name: ctx.package.name, version: "2.0.0", description: "From a key"})
           )
           |> json_response(201)
           |> Map.fetch!("status") == "staged"
  end

  test "the override stages an organization's first public release for its members to approve",
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

  test "emergency mode stages organization-key exchanges and their docs", ctx do
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

  test "user OAuth with OTP publishes directly under the override", ctx do
    client = insert(:oauth_client)
    session = insert(:oauth_session, user: ctx.user, client_id: client.client_id)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        ctx.user,
        client.client_id,
        ["api:write"],
        "authorization_code",
        "test",
        user_session_id: session.id
      )

    result =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> put_req_header("x-hex-otp", Hexpm.Accounts.TFA.time_based_token(ctx.user.tfa.secret))
      |> post(
        "/api/publish",
        create_tar(%{name: ctx.package.name, version: "1.0.0", description: "Interactive"})
      )
      |> json_response(201)

    refute result["status"] == "staged"
    assert Repo.aggregate(Release, :count) == 1
  end

  test "package and organization settings explain the active override", ctx do
    put_feature_flag(:workload_identity, mode: :enabled)
    package = Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
    path = "/packages/#{ctx.package.name}/publish-approval"
    page = build_conn() |> test_login(ctx.user) |> get(path) |> html_response(200)
    assert page =~ "The registry requires approval"
    assert page =~ "Emergency publishing mode is active."

    package
    |> Ecto.Changeset.change(require_publish_approval: true)
    |> Repo.update!()

    confirmation =
      build_conn()
      |> test_login(ctx.user)
      |> get(path)
      |> html_response(200)

    modal =
      confirmation
      |> LazyHTML.from_document()
      |> LazyHTML.query("#disable-publish-approval-modal")

    assert LazyHTML.text(modal) =~ "Disable publish approval"

    assert LazyHTML.text(modal) =~
             "Publish approval is currently enabled for #{ctx.package.name}."

    assert LazyHTML.text(modal) =~ "The registry requires approval"

    repository = insert(:repository)

    insert(:organization_user,
      organization: repository.organization,
      user: ctx.user,
      role: "admin"
    )

    path = "/dashboard/orgs/#{repository.name}/publish-approval"
    page = build_conn() |> test_login(ctx.user) |> get(path) |> html_response(200)
    assert page =~ "The registry currently requires approval"
    refute repository.organization.require_publish_approval

    repository.organization
    |> Ecto.Changeset.change(require_publish_approval: true)
    |> Repo.update!()

    confirmation =
      build_conn()
      |> test_login(ctx.user)
      |> get(path)
      |> html_response(200)

    modal =
      confirmation
      |> LazyHTML.from_document()
      |> LazyHTML.query("#disable-publish-approval-modal")

    assert LazyHTML.text(modal) =~ "Disable organization approval"

    assert LazyHTML.text(modal) =~
             "Publish approval is currently enabled for #{repository.organization.name}."

    assert LazyHTML.text(modal) =~ "The registry currently requires approval"
  end

  test "approval settings outside the rollout stay hidden while the override is active", ctx do
    build_conn()
    |> test_login(ctx.user)
    |> get("/packages/#{ctx.package.name}/publish-approval")
    |> response(404)
  end

  test "public API-key docs replacements stage and automated reverts are refused", ctx do
    package = Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
    release = insert(:release, package: package, version: "1.0.0")
    key = insert(:key, user: ctx.user)
    {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Replacement docs"}])

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key.user_secret)

    path = "/api/packages/#{package.name}/releases/1.0.0"

    staged = conn |> post(path <> "/docs", docs) |> json_response(201)
    assert staged["status"] == "staged"
    assert StagedReleases.get(staged["id"]).kind == "docs"
    refute Repo.get!(Release, release.id).has_docs
    conn |> delete(path) |> response(403)
    conn |> delete(path <> "/docs") |> response(403)
  end

  for credential <- [:key, :workload_identity] do
    test "emergency mode stages private #{credential} releases and docs without individual policies",
         ctx do
      repository = insert(:repository)

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "write"
      )

      package = insert(:package, repository_id: repository.id, require_publish_approval: false)

      authorization =
        case unquote(credential) do
          :key ->
            insert(:key, organization: repository.organization, user: nil).user_secret

          :workload_identity ->
            put_feature_flag(:workload_identity, mode: :enabled)

            insert(:organization_workload_identity,
              organization: repository.organization,
              role: "write",
              covers_private: true,
              repositories: [
                %Hexpm.WorkloadIdentities.TrustedRepository{name: "acme/widget", id: "67890"}
              ],
              workflow: "release.yml"
            )

            oidc =
              WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

            {:ok, token} =
              Hexpm.WorkloadIdentities.verify_and_mint(oidc,
                repository: repository.name,
                package: package.name
              )

            "Bearer #{token.access_token}"
        end

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", authorization)

      path = "/api/repos/#{repository.name}/packages/#{package.name}/releases"

      staged =
        conn
        |> post(
          path,
          create_tar(%{name: package.name, version: "1.0.0", description: "Private CI"})
        )
        |> json_response(201)

      assert staged["status"] == "staged"
      assert Repo.aggregate(Release, :count) == 0
      {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Private docs"}])
      staged = conn |> post(path <> "/1.0.0/docs", docs) |> json_response(201)

      build_conn()
      |> test_login(ctx.user)
      |> post("/dashboard/staged-releases/#{staged["id"]}/approve", %{
        checksum: staged["approval_checksum"]
      })
      |> response(302)

      assert Repo.one!(Release).has_docs
      refute repository.organization.require_publish_approval

      if unquote(credential) == :key do
        conn |> delete(path <> "/1.0.0") |> response(403)
        conn |> delete(path <> "/1.0.0/docs") |> response(403)
      end
    end
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
end
