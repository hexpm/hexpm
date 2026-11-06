defmodule HexpmWeb.StagedReleaseControllerTest do
  use HexpmWeb.ConnCase

  @revert_blocked "This package uses staged publishing, so API keys can't revert it. " <>
                    "Revert with your Hex account and a two-factor code."

  alias Hexpm.Accounts.{AuditLog, Key, User}
  alias Hexpm.Repository.{Assets, Package, Release, StagedRelease, StagedReleases}

  setup do
    put_feature_flag(:workload_identity, mode: :enabled)
    user = insert(:user_with_tfa)

    repository =
      insert(:repository, organization: build(:organization, require_staged_publishing: true))

    insert(:organization_user, organization: repository.organization, user: user, role: "write")
    key = insert(:key, user: user)
    %{user: user, repository: repository, key: key, name: Fake.sequence(:package)}
  end

  test "stages a new package without publishing its name, release, registry or tarball", ctx do
    {result, body} = stage(ctx)
    staged = staged(ctx, result)
    path = "#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0/staged"
    assert result["status"] == "staged"
    assert result["url"] == HexpmWeb.Endpoint.url() <> "/api/repos/#{path}"

    assert result["html_url"] ==
             HexpmWeb.Endpoint.url() <>
               "/dashboard/staged-releases/#{ctx.repository.name}/#{ctx.name}/1.0.0"

    refute Map.has_key?(result, "id")
    assert result["expires_at"]
    assert result["checksum"] == Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    refute Repo.get_by(Package, repository_id: ctx.repository.id, name: ctx.name)

    refute Hexpm.Store.get(
             :repo_bucket,
             "repos/#{ctx.repository.name}/tarballs/#{ctx.name}-1.0.0.tar"
           )

    assert "staged/" <> _ = staged.storage_key
    assert Hexpm.Store.get(:repo_bucket, staged.storage_key) == body
    assert Repo.aggregate(Release, :count) == 0
    assert Repo.aggregate(AuditLog, :count, :id) == 1
    assert Repo.one!(AuditLog).action == "release.stage"
    assert [%{category: "staged_release.staged"}] = Repo.all(Hexpm.Emails.OutboxEntry)
    assert [] = Repo.all(from(j in Oban.Job, where: j.queue == "registry"))
  end

  test "approval publishes package and docs together and records uploader and approver", ctx do
    {result, body} = stage(ctx)
    docs = docs_tar()

    docs_result =
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs) |> json_response(201)

    staged = staged(ctx, result)
    assert Hexpm.Store.get(:repo_bucket, staged.docs_storage_key) == docs
    assert docs_result["url"] == result["url"]
    refute docs_result["approval_checksum"] == result["approval_checksum"]

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get(html_path(result))
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ ctx.name
    assert LazyHTML.text(page) =~ "Release and documentation"
    refute LazyHTML.text(page) =~ "Release replacement"
    assert page |> LazyHTML.query("#sidebar-content") |> LazyHTML.text() =~ "Staged releases"

    assert page
           |> LazyHTML.query(~s(#review-actions input[type="hidden"][name="checksum"]))
           |> LazyHTML.attribute("value") ==
             [docs_result["approval_checksum"], docs_result["approval_checksum"]]

    refute LazyHTML.text(page) =~ "Approval checksum"
    refute LazyHTML.text(page) =~ docs_result["approval_checksum"]
    verification = LazyHTML.query(page, "#verify-downloads")
    assert page |> LazyHTML.query("section#verify-downloads") |> Enum.count() == 1
    assert LazyHTML.text(verification) =~ "publishing command's output"
    assert LazyHTML.text(verification) =~ result["checksum"]
    assert LazyHTML.text(verification) =~ Base.encode16(:crypto.hash(:sha256, docs), case: :lower)
    assert LazyHTML.text(verification) =~ "shasum -a 256 release.tar"
    assert LazyHTML.text(verification) =~ "shasum -a 256 docs.tar.gz"
    files = LazyHTML.query(page, "details[open]")
    assert LazyHTML.text(files) =~ "Files in this package (1)"
    assert files |> LazyHTML.query("li") |> LazyHTML.text() == "mix.exs"
    refute LazyHTML.text(page) =~ "%{"

    approve(ctx, docs_result) |> response(302)

    refute staged(ctx, result)
    package = Hexpm.Repository.Packages.get(ctx.repository, ctx.name)
    release = Hexpm.Repository.Releases.get(package, "1.0.0")
    assert release.publisher_id == ctx.user.id
    assert release.approved_by_id == ctx.user.id
    assert release.has_docs
    assert Hexpm.Store.get(:repo_bucket, Assets.tarball_store_key(release)) == body
    assert Hexpm.Store.get(:repo_bucket, Assets.docs_store_key(release)) == docs

    assert Repo.all(
             from(l in AuditLog,
               where: l.action != "session.create",
               order_by: l.id,
               select: l.action
             )
           ) ==
             [
               "release.stage",
               "release.stage",
               "release.publish",
               "release.approve",
               "docs.publish"
             ]

    Oban.drain_queue(queue: :heavy)
    refute Hexpm.Store.get(:repo_bucket, staged.storage_key)
    refute Hexpm.Store.get(:repo_bucket, staged.docs_storage_key)
    assert Hexpm.Store.get(:repo_bucket, Assets.tarball_store_key(release)) == body
    assert Hexpm.Store.get(:repo_bucket, Assets.docs_store_key(release)) == docs
    assert read(ctx, result) |> json_response(200) |> Map.fetch!("status") == "approved"
  end

  test "requires fresh sudo even when rolling sudo is active", ctx do
    {result, _} = stage(ctx)

    conn =
      build_conn()
      |> test_login(ctx.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60))

    response =
      post(conn, html_path(result) <> "/approve", %{
        checksum: result["approval_checksum"]
      })

    assert redirected_to(response) == "/sudo"
    assert get_session(response, "sudo_force")
    assert staged(ctx, result)

    for download <- ["release.tar", "docs.tar.gz"] do
      response = get(conn, html_path(result) <> "/#{download}")
      assert redirected_to(response) == "/sudo"
    end
  end

  for format <- [:map, :list] do
    test "the review summarizes #{format}-form dependencies with their repositories", ctx do
      dependency = insert(:package)
      private_dependency = insert(:package, repository_id: ctx.repository.id)

      requirements = %{
        dependency.name => %{
          app: dependency.name,
          requirement: "~> 1.0",
          optional: true,
          repository: "hexpm"
        },
        private_dependency.name => %{
          app: private_dependency.name,
          requirement: "~> 2.0",
          optional: false,
          repository: ctx.repository.name
        }
      }

      requirements =
        case unquote(format) do
          :map -> requirements
          :list -> Enum.map(requirements, fn {name, attrs} -> Map.put(attrs, :name, name) end)
        end

      body =
        create_tar(%{
          name: ctx.name,
          version: "1.0.0",
          description: "Package with dependencies",
          licenses: [],
          elixir: "~> 1.14",
          links: %{"Source" => "https://github.com/hexpm/hexpm"},
          requirements: requirements
        })

      result = upload(ctx, "/packages/#{ctx.name}/releases", body) |> json_response(201)

      page =
        build_conn()
        |> test_login(ctx.user)
        |> get(html_path(result))
        |> html_response(200)
        |> LazyHTML.from_document()

      text = LazyHTML.text(page)
      assert text =~ "Build tools"
      assert text =~ "mix"
      assert text =~ dependency.name
      assert text =~ "#{ctx.repository.name}/#{private_dependency.name}"
      assert text =~ "~> 1.0"
      assert text =~ "~> 2.0"
      assert text =~ "Optional"
      refute text =~ "Licenses"
      assert text =~ "~> 1.14"

      assert page
             |> LazyHTML.query(~s(a[href="https://github.com/hexpm/hexpm"]))
             |> LazyHTML.text() =~ "Source"

      refute text =~ "%{"
    end
  end

  test "a restage invalidates the displayed checksum and keeps the same reservation", ctx do
    {first, _} = stage(ctx)
    id = staged(ctx, first).id
    {second, second_body} = stage(ctx, "second")
    assert second["url"] == first["url"]
    assert staged(ctx, second).id == id
    refute second["checksum"] == first["checksum"]
    approve(ctx, first) |> response(409)
    assert staged(ctx, first)
    approve(ctx, second) |> response(302)
    release = Repo.one!(Release) |> Repo.preload(package: :repository)
    assert Hexpm.Store.get(:repo_bucket, Assets.tarball_store_key(release)) == second_body
  end

  test "an outdated review page can't reject a restaged release", ctx do
    {first, _} = stage(ctx)
    {second, _} = stage(ctx, "second")
    reject(ctx, first) |> response(409)
    assert staged(ctx, second)
    reject(ctx, second) |> response(302)
    refute staged(ctx, second)
  end

  test "an outdated review page can't approve identical bytes staged again by another credential",
       ctx do
    {first, body} = stage(ctx)
    reject(ctx, first) |> response(302)

    second =
      %{ctx | key: insert(:key, user: ctx.user)}
      |> upload("/packages/#{ctx.name}/releases", body)
      |> json_response(201)

    assert second["html_url"] == first["html_url"]
    assert second["checksum"] == first["checksum"]
    refute second["approval_checksum"] == first["approval_checksum"]
    approve(ctx, first) |> response(409)
    assert staged(ctx, second)
    approve(ctx, second) |> response(302)
  end

  test "approval refuses a revoked key and leaves the staged release intact", ctx do
    {result, _} = stage(ctx)
    Repo.update!(Key.revoke(ctx.key))
    approve(ctx, result) |> response(409)
    assert staged(ctx, result)
    refute Repo.get_by(Package, repository_id: ctx.repository.id, name: ctx.name)
  end

  test "approval refuses a publisher who lost organization access", ctx do
    {result, _} = stage(ctx)
    reviewer = insert(:user_with_tfa)

    insert(:organization_user,
      organization: ctx.repository.organization,
      user: reviewer,
      role: "write"
    )

    Repo.delete_all(from(m in Hexpm.Accounts.OrganizationUser, where: m.user_id == ^ctx.user.id))
    approve(%{ctx | user: reviewer}, result) |> response(409)
    assert staged(ctx, result)
  end

  test "approval rejects modified bytes even when the submitted checksum matches the row", ctx do
    {result, _} = stage(ctx)
    staged = staged(ctx, result)
    Hexpm.Store.put(:repo_bucket, staged.storage_key, "modified")
    approve(ctx, result) |> response(409)
    assert staged(ctx, result)
    assert Repo.aggregate(Release, :count) == 0
  end

  test "staged docs for a published release don't replace the public docs until approval", ctx do
    package = insert(:package, name: ctx.name, repository_id: ctx.repository.id)

    release =
      insert(:release, package: package, version: "1.0.0", has_docs: true)
      |> Repo.preload(package: :repository)

    Hexpm.Store.put(:repo_bucket, Assets.docs_store_key(release), "previous")

    conn = upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar())
    result = json_response(conn, 201)
    version_path = "#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0"
    assert result["kind"] == "docs"
    assert result["url"] == HexpmWeb.Endpoint.url() <> "/api/repos/#{version_path}/docs/staged"
    assert get_resp_header(conn, "location") == [result["url"]]

    assert result["html_url"] ==
             HexpmWeb.Endpoint.url() <>
               "/dashboard/staged-releases/#{ctx.repository.name}/#{ctx.name}/1.0.0/docs"

    assert Hexpm.Store.get(:repo_bucket, Assets.docs_store_key(release)) == "previous"

    build_conn()
    |> put_req_header("authorization", ctx.key.user_secret)
    |> get("/api/repos/#{version_path}/staged")
    |> json_response(404)

    build_conn()
    |> test_login(ctx.user)
    |> get("/dashboard/staged-releases/#{ctx.repository.name}/#{ctx.name}/1.0.0")
    |> response(404)

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get(html_path(result))
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ "Only documentation was staged, for an existing release"
    assert LazyHTML.text(page) =~ "Approval replaces any documentation already published"
    refute LazyHTML.text(page) =~ "Package contents"

    assert page |> LazyHTML.query(~s(input[name="checksum"])) |> LazyHTML.attribute("value") ==
             [result["approval_checksum"], result["approval_checksum"]]

    for action <- ["approve", "reject"] do
      assert page
             |> LazyHTML.query(~s(form[action="#{html_path(result)}/#{action}"]))
             |> Enum.count() == 1
    end

    download = "#{html_path(result)}/docs.tar.gz"
    assert page |> LazyHTML.query(~s(a[href="#{download}"])) |> Enum.count() == 1
    assert build_conn() |> test_login(ctx.user) |> get(download) |> response(200) == docs_tar()

    approve(ctx, result) |> response(302)
    assert Hexpm.Store.get(:repo_bucket, Assets.docs_store_key(release)) == docs_tar()
    assert Repo.aggregate(Release, :count) == 1
    assert read(ctx, result) |> json_response(200) |> Map.fetch!("status") == "approved"
  end

  test "rejection frees the reserved version and the polling endpoint reports rejected", ctx do
    {result, _} = stage(ctx)

    reject(ctx, result) |> response(302)

    refute staged(ctx, result)
    rejected = read(ctx, result) |> json_response(200)
    assert rejected["status"] == "rejected"
    assert rejected["approval_checksum"] == result["approval_checksum"]

    {restaged, _} = stage(ctx, "second")
    assert restaged["url"] == result["url"]
    assert restaged["html_url"] == result["html_url"]
    refute restaged["approval_checksum"] == result["approval_checksum"]
    staged = read(ctx, restaged) |> json_response(200)
    assert staged["status"] == "staged"
    assert staged["approval_checksum"] == restaged["approval_checksum"]

    approve(ctx, restaged) |> response(302)
    approved = read(ctx, restaged) |> json_response(200)
    assert approved["status"] == "approved"
    assert approved["approval_checksum"] == restaged["approval_checksum"]
  end

  test "expiry refuses approval, removes the row and tarball, and records expiry", ctx do
    {result, _} = stage(ctx)
    staged = staged(ctx, result)
    Repo.update!(Ecto.Changeset.change(staged, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    approve(ctx, result) |> response(409)
    assert :ok = Hexpm.Repository.StagedReleaseExpiryWorker.perform(%Oban.Job{})
    refute staged(ctx, result)
    Oban.drain_queue(queue: :heavy)
    refute Hexpm.Store.get(:repo_bucket, staged.storage_key)
    assert read(ctx, result) |> json_response(200) |> Map.fetch!("status") == "expired"
    assert Repo.exists?(from(l in AuditLog, where: l.action == "release.stage_expire"))
  end

  test "staging and expiry leave out approvers who turned them off", ctx do
    other = insert(:user_with_tfa, optional_emails: %{"staged_releases" => false})

    insert(:organization_user,
      organization: ctx.repository.organization,
      user: other,
      role: "write"
    )

    {result, _} = stage(ctx)

    assert [staged_entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    assert staged_entry.category == "staged_release.staged"
    assert staged_entry.recipients == [User.email(ctx.user, :primary)]

    staged = staged(ctx, result)
    Repo.update!(Ecto.Changeset.change(staged, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    assert :ok = Hexpm.Repository.StagedReleaseExpiryWorker.perform(%Oban.Job{})

    expired_entry = Repo.get_by!(Hexpm.Emails.OutboxEntry, category: "staged_release.expired")
    assert expired_entry.recipients == [User.email(ctx.user, :primary)]
  end

  test "staging and expiry send nothing when every approver turned them off", ctx do
    ctx.user
    |> Ecto.Changeset.change(optional_emails: %{"staged_releases" => false})
    |> Repo.update!()

    {result, _} = stage(ctx)
    staged = staged(ctx, result)
    Repo.update!(Ecto.Changeset.change(staged, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    assert :ok = Hexpm.Repository.StagedReleaseExpiryWorker.perform(%Oban.Job{})

    assert Repo.all(Hexpm.Emails.OutboxEntry) == []
  end

  test "a user without 2FA or with only read access can't review or approve", ctx do
    {result, _} = stage(ctx)

    for user <- [insert(:user), insert(:user_with_tfa)] do
      insert(:organization_user,
        organization: ctx.repository.organization,
        user: user,
        role: "read"
      )

      build_conn()
      |> test_login(user)
      |> get(html_path(result))
      |> response(404)

      approve(%{ctx | user: user}, result) |> response(404)

      build_conn()
      |> test_login(user)
      |> get(html_path(result) <> "/release.tar")
      |> response(404)
    end
  end

  test "a direct publish can't replace a reserved version after the rollout is turned off", ctx do
    {result, _} = stage(ctx)
    put_feature_flag(:workload_identity, mode: :off)

    upload(
      ctx,
      "/packages/#{ctx.name}/releases",
      create_tar(%{name: ctx.name, version: "1.0.0", description: "Direct"})
    )
    |> response(422)

    assert staged(ctx, result)
  end

  test "validation rejects invalid metadata without reserving the package", ctx do
    upload(
      ctx,
      "/packages/#{ctx.name}/releases",
      create_tar(%{name: ctx.name, version: "invalid", description: "Staged package"})
    )
    |> response(422)

    assert Repo.aggregate(StagedRelease, :count) == 0
    refute Repo.get_by(Package, repository_id: ctx.repository.id, name: ctx.name)
  end

  test "the dashboard lists releases the user can approve", ctx do
    {result, _} = stage(ctx)
    conn = build_conn() |> test_login(ctx.user) |> get("/dashboard/staged-releases")
    page = conn |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(page, "#sidebar-content") |> LazyHTML.text() =~ "Staged releases"

    assert page
           |> LazyHTML.query(~s(a[href="#{html_path(result)}"]))
           |> LazyHTML.text() =~ "Review release"

    assert LazyHTML.text(page) =~
             HexpmWeb.ViewHelpers.pretty_utc_datetime(staged(ctx, result).expires_at)

    outsider = insert(:user_with_tfa)
    conn = build_conn() |> test_login(outsider) |> get("/dashboard/staged-releases")
    refute html_response(conn, 200) =~ html_path(result)
  end

  test "organization keys stage and retain the organization's publisher", ctx do
    key = insert(:key, organization: ctx.repository.organization)
    {result, _} = stage(%{ctx | key: key})
    approve(ctx, result) |> response(302)
    release = Repo.one!(Release)
    assert release.publisher_id == ctx.repository.organization.user.id
    assert release.approved_by_id == ctx.user.id
  end

  test "an exchanged organization key stages publishing and can't revert", ctx do
    key = insert(:key, organization: ctx.repository.organization)

    client =
      insert(:oauth_client,
        allowed_grant_types: ["client_credentials"],
        allowed_scopes: ["api:write"]
      )

    token =
      build_conn()
      |> post("/api/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => client.client_id,
        "client_secret" => key.user_secret,
        "scope" => "api:write"
      })
      |> json_response(200)
      |> Map.fetch!("access_token")

    body = create_tar(%{name: ctx.name, version: "1.0.0", description: "Exchanged key"})

    result =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> post("/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases", body)
      |> json_response(201)

    assert result["status"] == "staged"
    assert staged(ctx, result).key_id == key.id
    assert Repo.aggregate(Release, :count) == 0

    docs =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> post(
        "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0/docs",
        docs_tar()
      )
      |> json_response(201)

    assert docs["url"] == result["url"]
    approve(ctx, docs) |> response(302)

    for suffix <- ["", "/docs"] do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(
          "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0#{suffix}"
        )

      assert json_response(conn, 403)["message"] == @revert_blocked
    end

    assert Repo.one!(Release).has_docs
  end

  test "approval of an exchanged organization key revalidates the underlying key", ctx do
    key = insert(:key, organization: ctx.repository.organization)

    client =
      insert(:oauth_client,
        allowed_grant_types: ["client_credentials"],
        allowed_scopes: ["api:write"]
      )

    token =
      build_conn()
      |> post("/api/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => client.client_id,
        "client_secret" => key.user_secret,
        "scope" => "api:write"
      })
      |> json_response(200)
      |> Map.fetch!("access_token")

    result =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> post(
        "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases",
        create_tar(%{name: ctx.name, version: "1.0.0"})
      )
      |> json_response(201)

    Repo.update!(Key.revoke(key))
    approve(ctx, result) |> response(409)
    assert staged(ctx, result)
    assert Repo.aggregate(Release, :count) == 0
  end

  test "attaching docs doesn't send a duplicate approval email", ctx do
    {result, _} = stage(ctx)
    count = Repo.aggregate(Hexpm.Emails.OutboxEntry, :count)

    docs =
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar()) |> json_response(201)

    assert docs["url"] == result["url"]
    assert Repo.aggregate(Hexpm.Emails.OutboxEntry, :count) == count
  end

  test "API keys can't revert releases or docs while the organization policy is active", ctx do
    package = insert(:package, name: ctx.name, repository_id: ctx.repository.id)
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    path = "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0"

    for suffix <- ["", "/docs"] do
      conn =
        build_conn()
        |> put_req_header("authorization", ctx.key.user_secret)
        |> delete(path <> suffix)

      assert json_response(conn, 403)["message"] == @revert_blocked
    end

    assert Repo.get!(Release, release.id).has_docs
  end

  test "OAuth publishing with OTP bypasses staging and clears a replaced release's approver",
       ctx do
    {result, _} = stage(ctx)
    approve(ctx, result) |> response(302)
    client = insert(:oauth_client)
    session = insert(:oauth_session, user: ctx.user, client_id: client.client_id)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        ctx.user,
        client.client_id,
        ["api:write"],
        "authorization_code",
        "staged-oauth",
        user_session_id: session.id
      )

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("x-hex-otp", Hexpm.Accounts.TFA.time_based_token(ctx.user.tfa.secret))
      |> post(
        "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases",
        create_tar(%{name: ctx.name, version: "1.0.0", description: "Published with OTP"})
      )

    refute json_response(conn, 200)["status"] == "staged"
    assert Repo.one!(Release).approved_by_id == nil
  end

  test "private packages follow the organization beta list", ctx do
    put_feature_flag(:workload_identity,
      mode: :beta,
      beta_users: [ctx.user.username],
      beta_organizations: []
    )

    {direct, _} = stage(ctx)
    refute direct["status"] == "staged"
    put_feature_flag(:workload_identity, beta_organizations: [ctx.repository.organization.name])

    result =
      upload(
        ctx,
        "/packages/#{ctx.name}/releases",
        create_tar(%{name: ctx.name, version: "2.0.0", description: "Beta"})
      )
      |> json_response(201)

    assert result["status"] == "staged"
  end

  test "an explicit private package maintainer receives a notification and can approve", ctx do
    maintainer = insert(:user_with_tfa)

    insert(:organization_user,
      organization: ctx.repository.organization,
      user: maintainer,
      role: "read"
    )

    insert(:package,
      name: ctx.name,
      repository_id: ctx.repository.id,
      package_owners: [build(:package_owner, user: maintainer, level: "maintainer")]
    )

    {result, _} = stage(ctx)
    email = Repo.one!(Hexpm.Emails.OutboxEntry)
    assert Hexpm.Accounts.User.email(maintainer, :primary) in email.recipients
    approve(%{ctx | user: maintainer}, result) |> response(302)
    terminal = read(ctx, result) |> json_response(200)
    assert terminal["checksum"] == result["checksum"]
    assert terminal["approval_checksum"] == result["approval_checksum"]
    assert terminal["expires_at"] == result["expires_at"]
  end

  test "stores Hex build metadata and approves the same package", ctx do
    body =
      create_tar(%{
        name: ctx.name,
        version: "1.0.0",
        build_env: %{hex: "2.7.0-dev"},
        description: "From Hex"
      })

    result = upload(ctx, "/packages/#{ctx.name}/releases", body) |> json_response(201)
    staged = staged(ctx, result)
    assert staged.meta["build_env"] == [["hex", "2.7.0-dev"]]
    approve(ctx, result) |> response(302)
    assert Repo.one!(Package).meta.description == "From Hex"
  end

  test "stages a valid replacement and revalidates its replace flag", ctx do
    package = insert(:package, name: ctx.name, repository_id: ctx.repository.id)
    release = insert(:release, package: package, version: "1.0.0")
    body = create_tar(%{name: ctx.name, version: "1.0.0", description: "Replacement"})

    upload(ctx, "/packages/#{ctx.name}/releases?replace=false", body) |> json_response(422)

    result =
      upload(ctx, "/packages/#{ctx.name}/releases?replace=true", body) |> json_response(201)

    assert Repo.get!(Release, release.id).outer_checksum == release.outer_checksum
    assert staged(ctx, result).replace

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get(html_path(result))
      |> html_response(200)

    assert page =~ "Release replacement"
    assert page =~ "Approval replaces the published package files for this version"

    approve(ctx, result) |> response(302)
    assert Repo.aggregate(Release, :count) == 1
    assert Repo.get!(Release, release.id).outer_checksum == :crypto.hash(:sha256, body)
  end

  test "a second key can't overwrite another key's package reservation", ctx do
    {result, body} = stage(ctx)
    other = insert(:key, user: ctx.user)
    replacement = create_tar(%{name: ctx.name, version: "1.0.0", description: "Other key"})

    upload(%{ctx | key: other}, "/packages/#{ctx.name}/releases", replacement)
    |> json_response(422)

    staged = staged(ctx, result)
    assert staged.key_id == ctx.key.id
    assert Hexpm.Store.get(:repo_bucket, staged.storage_key) == body
  end

  test "a second key can't overwrite another key's docs reservation", ctx do
    package = insert(:package, name: ctx.name, repository_id: ctx.repository.id)
    insert(:release, package: package, version: "1.0.0")

    result =
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar()) |> json_response(201)

    other = insert(:key, user: ctx.user)

    upload(%{ctx | key: other}, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar())
    |> json_response(422)

    assert staged(ctx, result).key_id == ctx.key.id
  end

  test "another credential can't tell a staged new public package from a missing one", ctx do
    name = Fake.sequence(:package)
    body = create_tar(%{name: name, version: "1.0.0", description: "Staged package"})

    assert public_upload(ctx.key, "/api/publish", body)
           |> json_response(201)
           |> Map.fetch!("status") == "staged"

    other = insert(:key, user: insert(:user))

    for version <- ["1.0.0", "2.0.0"] do
      public_upload(other, "/api/packages/#{name}/releases/#{version}/docs", docs_tar())
      |> json_response(404)
    end

    assert public_upload(ctx.key, "/api/packages/#{name}/releases/1.0.0/docs", docs_tar())
           |> json_response(201)
           |> Map.fetch!("kind") == "release"
  end

  test "approval creates a staged new public package owned by the chosen organization", ctx do
    organization = ctx.repository.organization
    name = Fake.sequence(:package)
    body = create_tar(%{name: name, version: "1.0.0", description: "Staged package"})

    result =
      public_upload(ctx.key, "/api/publish?owner=#{organization.name}", body)
      |> json_response(201)

    assert result["status"] == "staged"
    staged = StagedReleases.get("hexpm", name, "1.0.0", "release")
    assert staged.owner_id == organization.id

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get(html_path(result))
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ "Package owner"
    assert LazyHTML.text(page) =~ organization.name

    approve(ctx, result) |> response(302)

    package = Repo.get_by!(Package, repository_id: 1, name: name)
    assert [owner] = Repo.all(assoc(package, :package_owners))
    assert owner.user_id == organization.user.id
    assert Hexpm.Repository.Releases.get(package, "1.0.0").publisher_id == ctx.user.id
  end

  test "a restage that changes the owner invalidates the displayed checksum", ctx do
    organization = ctx.repository.organization
    name = Fake.sequence(:package)
    body = create_tar(%{name: name, version: "1.0.0", description: "Staged package"})

    first =
      public_upload(ctx.key, "/api/publish?owner=#{organization.name}", body)
      |> json_response(201)

    second = public_upload(ctx.key, "/api/publish", body) |> json_response(201)
    refute first["approval_checksum"] == second["approval_checksum"]

    approve(ctx, first) |> response(409)
    refute Repo.get_by(Package, repository_id: 1, name: name)
  end

  test "approval refuses an owner the publisher lost write access to", ctx do
    organization = ctx.repository.organization
    name = Fake.sequence(:package)
    body = create_tar(%{name: name, version: "1.0.0", description: "Staged package"})

    result =
      public_upload(ctx.key, "/api/publish?owner=#{organization.name}", body)
      |> json_response(201)

    Repo.update_all(
      from(m in Hexpm.Accounts.OrganizationUser, where: m.user_id == ^ctx.user.id),
      set: [role: "read"]
    )

    assert approve(ctx, result) |> response(409) =~ "no longer passes publish validation"
    refute Repo.get_by(Package, repository_id: 1, name: name)
    assert StagedReleases.get("hexpm", name, "1.0.0", "release")
  end

  test "a staged replacement of a public release expires when the release stops being editable",
       ctx do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    package =
      insert(:package,
        require_staged_publishing: true,
        inserted_at: NaiveDateTime.add(now, -2 * 24 * 60 * 60),
        package_owners: [build(:package_owner, user: ctx.user)]
      )

    release =
      insert(:release,
        package: package,
        version: "1.0.0",
        inserted_at: NaiveDateTime.add(now, -30 * 60)
      )

    body = create_tar(%{name: package.name, version: "1.0.0", description: "Replacement"})
    result = public_upload(ctx.key, "/api/publish?replace=true", body) |> json_response(201)
    assert result["status"] == "staged"

    deadline = DateTime.from_naive!(NaiveDateTime.add(release.inserted_at, 60 * 60), "Etc/UTC")
    staged = StagedReleases.get("hexpm", package.name, "1.0.0", "release")
    assert abs(DateTime.diff(staged.expires_at, deadline)) <= 1
  end

  test "an artifact upload failure leaves approval pending for retry", ctx do
    {result, _} = stage(ctx)
    app_env(:hexpm, :repo_bucket, {Hexpm.Store.Mock, "repo_bucket"})
    Mox.stub(Hexpm.Store.Mock, :get_to_file, &Hexpm.Store.Memory.get_to_file/4)
    Mox.expect(Hexpm.Store.Mock, :put_file, fn _, _, _, _ -> raise "store unavailable" end)

    assert_raise RuntimeError, "store unavailable", fn ->
      StagedReleases.approve(staged(ctx, result).id, ctx.user, result["approval_checksum"],
        audit: audit_data(ctx.user)
      )
    end

    assert staged(ctx, result)
    assert Repo.exists?(from(l in AuditLog, where: l.action == "release.approve"))
    assert Repo.aggregate(Release, :count) == 1
    assert read(ctx, result) |> json_response(200) |> Map.fetch!("status") == "staged"

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get(html_path(result))
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ "Retry publication"
    refute LazyHTML.text(page) =~ "Reject publication"
    refute LazyHTML.text(page) =~ "Expires"

    list =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(list) =~ "Publication in progress"
    refute LazyHTML.text(list) =~ "Expires"

    client = insert(:oauth_client)
    session = insert(:oauth_session, user: ctx.user, client_id: client.client_id)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        ctx.user,
        client.client_id,
        ["api:write"],
        "authorization_code",
        "pending-publication",
        user_session_id: session.id
      )

    for suffix <- ["", "/docs"] do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", Hexpm.Accounts.TFA.time_based_token(ctx.user.tfa.secret))
        |> delete(
          "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0#{suffix}"
        )

      assert json_response(conn, 422)["errors"]["version"] == "is being published"
    end

    assert Repo.aggregate(Release, :count) == 1
    Mox.verify!()
    app_env(:hexpm, :repo_bucket, {Hexpm.Store.Memory, "repo_bucket"})
    Oban.drain_queue(queue: :heavy)
    refute staged(ctx, result)
    assert read(ctx, result) |> json_response(200) |> Map.fetch!("status") == "approved"
  end

  for operation <- [:delete, :delete_data] do
    test "organization #{operation} removes staged artifacts", ctx do
      {result, _} = stage(ctx)
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar()) |> json_response(201)
      staged = staged(ctx, result)

      assert :ok =
               apply(Hexpm.Accounts.Organizations, unquote(operation), [
                 ctx.repository.organization,
                 [audit: audit_data(ctx.user)]
               ])

      refute StagedReleases.get(staged.id)
      Oban.drain_queue(queue: :heavy)
      refute Hexpm.Store.get(:repo_bucket, staged.storage_key)
      refute Hexpm.Store.get(:repo_bucket, staged.docs_storage_key)
    end
  end

  test "deleting an organization removes the staged new packages it would own", ctx do
    organization = ctx.repository.organization
    name = Fake.sequence(:package)
    body = create_tar(%{name: name, version: "1.0.0", description: "Staged package"})
    public_upload(ctx.key, "/api/publish?owner=#{organization.name}", body) |> json_response(201)
    staged = StagedReleases.get("hexpm", name, "1.0.0", "release")

    assert :ok =
             Hexpm.Accounts.Organizations.delete(organization, audit: audit_data(ctx.user))

    refute StagedReleases.get(staged.id)
    Oban.drain_queue(queue: :heavy)
    refute Hexpm.Store.get(:repo_bucket, staged.storage_key)
  end

  test "the settings navigation marks staged releases as new", ctx do
    nav =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#sidebar-content")

    link = LazyHTML.query(nav, ~s(a[href="/dashboard/staged-releases"]))
    assert link |> LazyHTML.query("span:last-child") |> LazyHTML.text() |> String.trim() == "NEW"
    assert [class] = LazyHTML.attribute(link, "class")
    assert class =~ "text-purple-600"
  end

  defp stage(ctx, text \\ "first") do
    body =
      create_tar(%{name: ctx.name, version: "1.0.0", description: "Staged package"}, [
        {"mix.exs", text}
      ])

    {upload(ctx, "/packages/#{ctx.name}/releases", body) |> json_response(201), body}
  end

  defp upload(ctx, path, body) do
    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", ctx.key.user_secret)
    |> post("/api/repos/#{ctx.repository.name}#{path}", body)
  end

  defp public_upload(key, path, body) do
    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key.user_secret)
    |> post(path, body)
  end

  defp approve(ctx, result) do
    build_conn()
    |> test_login(ctx.user)
    |> post(html_path(result) <> "/approve", %{
      checksum: result["approval_checksum"]
    })
  end

  defp reject(ctx, result) do
    build_conn()
    |> test_login(ctx.user)
    |> post(html_path(result) <> "/reject", %{
      checksum: result["approval_checksum"]
    })
  end

  defp read(ctx, result),
    do:
      build_conn()
      |> put_req_header("authorization", ctx.key.user_secret)
      |> get(URI.parse(result["url"]).path)

  defp staged(ctx, result),
    do: StagedReleases.get(ctx.repository.name, result["name"], result["version"], result["kind"])

  defp html_path(result), do: URI.parse(result["html_url"]).path

  defp docs_tar do
    {:ok, body} = :hex_tarball.create_docs([{~c"index.html", "Documentation"}])
    body
  end
end
