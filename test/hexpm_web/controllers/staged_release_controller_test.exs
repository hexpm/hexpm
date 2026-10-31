defmodule HexpmWeb.StagedReleaseControllerTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.{AuditLog, Key}
  alias Hexpm.Repository.{Assets, Package, Release, StagedRelease, StagedReleases}

  setup do
    put_feature_flag(:workload_identity, mode: :enabled)
    user = insert(:user_with_tfa)

    repository =
      insert(:repository, organization: build(:organization, require_publish_approval: true))

    insert(:organization_user, organization: repository.organization, user: user, role: "write")
    key = insert(:key, user: user)
    %{user: user, repository: repository, key: key, name: Fake.sequence(:package)}
  end

  test "stages a new package without publishing its name, release, registry or tarball", ctx do
    {result, body} = stage(ctx)
    staged = StagedReleases.get(result["id"])
    assert result["status"] == "staged"
    assert result["html_url"] =~ "/dashboard/staged-releases/#{staged.id}"
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

    staged = StagedReleases.get(result["id"])
    assert Hexpm.Store.get(:repo_bucket, staged.docs_storage_key) == docs
    assert docs_result["id"] == result["id"]
    refute docs_result["approval_checksum"] == result["approval_checksum"]

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases/#{result["id"]}")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ ctx.name
    assert LazyHTML.text(page) =~ "Release and documentation"
    refute LazyHTML.text(page) =~ "Release replacement"
    assert page |> LazyHTML.query("#sidebar-content") |> LazyHTML.text() =~ "Staged releases"

    assert page
           |> LazyHTML.query(~s(#review-actions input[type="hidden"][name="checksum"]))
           |> LazyHTML.attribute("value") == [docs_result["approval_checksum"]]

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

    refute StagedReleases.get(result["id"])
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
    assert read(ctx, result["id"]) |> json_response(200) |> Map.fetch!("status") == "approved"
  end

  test "requires fresh sudo even when rolling sudo is active", ctx do
    {result, _} = stage(ctx)

    conn =
      build_conn()
      |> test_login(ctx.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60))

    response =
      post(conn, "/dashboard/staged-releases/#{result["id"]}/approve", %{
        checksum: result["approval_checksum"]
      })

    assert redirected_to(response) == "/sudo"
    assert get_session(response, "sudo_force")
    assert StagedReleases.get(result["id"])

    for download <- ["tarball", "docs"] do
      response = get(conn, "/dashboard/staged-releases/#{result["id"]}/#{download}")
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
        |> get("/dashboard/staged-releases/#{result["id"]}")
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
    {second, second_body} = stage(ctx, "second")
    assert second["id"] == first["id"]
    refute second["checksum"] == first["checksum"]
    approve(ctx, first) |> response(409)
    assert StagedReleases.get(first["id"])
    approve(ctx, second) |> response(302)
    release = Repo.one!(Release) |> Repo.preload(package: :repository)
    assert Hexpm.Store.get(:repo_bucket, Assets.tarball_store_key(release)) == second_body
  end

  test "approval refuses a revoked key and leaves the staged release intact", ctx do
    {result, _} = stage(ctx)
    Repo.update!(Key.revoke(ctx.key))
    approve(ctx, result) |> response(409)
    assert StagedReleases.get(result["id"])
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
    assert StagedReleases.get(result["id"])
  end

  test "approval rejects modified bytes even when the submitted checksum matches the row", ctx do
    {result, _} = stage(ctx)
    staged = StagedReleases.get(result["id"])
    Hexpm.Store.put(:repo_bucket, staged.storage_key, "modified")
    approve(ctx, result) |> response(409)
    assert StagedReleases.get(result["id"])
    assert Repo.aggregate(Release, :count) == 0
  end

  test "staged docs for a published release don't replace the public docs until approval", ctx do
    package = insert(:package, name: ctx.name, repository_id: ctx.repository.id)

    release =
      insert(:release, package: package, version: "1.0.0", has_docs: true)
      |> Repo.preload(package: :repository)

    Hexpm.Store.put(:repo_bucket, Assets.docs_store_key(release), "previous")

    result =
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar()) |> json_response(201)

    assert result["kind"] == "docs"
    assert Hexpm.Store.get(:repo_bucket, Assets.docs_store_key(release)) == "previous"

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases/#{result["id"]}")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ "Only documentation was staged, for an existing release"
    assert LazyHTML.text(page) =~ "Approval replaces any documentation already published"
    refute LazyHTML.text(page) =~ "Package contents"

    assert page |> LazyHTML.query(~s(input[name="checksum"])) |> LazyHTML.attribute("value") ==
             [result["approval_checksum"]]

    approve(ctx, result) |> response(302)
    assert Hexpm.Store.get(:repo_bucket, Assets.docs_store_key(release)) == docs_tar()
    assert Repo.aggregate(Release, :count) == 1
  end

  test "rejection frees the reserved version and the polling endpoint reports rejected", ctx do
    {result, _} = stage(ctx)

    build_conn()
    |> test_login(ctx.user)
    |> post("/dashboard/staged-releases/#{result["id"]}/reject")
    |> response(302)

    refute StagedReleases.get(result["id"])
    assert read(ctx, result["id"]) |> json_response(200) |> Map.fetch!("status") == "rejected"
    {restaged, _} = stage(ctx)
    refute restaged["id"] == result["id"]
  end

  test "expiry refuses approval, removes the row and tarball, and records expiry", ctx do
    {result, _} = stage(ctx)
    staged = StagedReleases.get(result["id"])
    Repo.update!(Ecto.Changeset.change(staged, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    approve(ctx, result) |> response(409)
    assert :ok = Hexpm.Repository.StagedReleaseExpiryWorker.perform(%Oban.Job{})
    refute StagedReleases.get(result["id"])
    Oban.drain_queue(queue: :heavy)
    refute Hexpm.Store.get(:repo_bucket, staged.storage_key)
    assert read(ctx, result["id"]) |> json_response(200) |> Map.fetch!("status") == "expired"
    assert Repo.exists?(from(l in AuditLog, where: l.action == "release.stage_expire"))
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
      |> get("/dashboard/staged-releases/#{result["id"]}")
      |> response(404)

      approve(%{ctx | user: user}, result) |> response(404)

      build_conn()
      |> test_login(user)
      |> get("/dashboard/staged-releases/#{result["id"]}/tarball")
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

    assert StagedReleases.get(result["id"])
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
           |> LazyHTML.query(~s(a[href="/dashboard/staged-releases/#{result["id"]}"]))
           |> LazyHTML.text() =~ "Review release"

    assert LazyHTML.text(page) =~
             HexpmWeb.ViewHelpers.pretty_utc_datetime(StagedReleases.get(result["id"]).expires_at)

    outsider = insert(:user_with_tfa)
    conn = build_conn() |> test_login(outsider) |> get("/dashboard/staged-releases")
    refute html_response(conn, 200) =~ "/dashboard/staged-releases/#{result["id"]}"
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
    assert StagedReleases.get(result["id"]).key_id == key.id
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

    assert docs["id"] == result["id"]
    approve(ctx, docs) |> response(302)

    for suffix <- ["", "/docs"] do
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete("/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0#{suffix}")
      |> response(403)
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
    assert StagedReleases.get(result["id"])
    assert Repo.aggregate(Release, :count) == 0
  end

  test "attaching docs doesn't send a duplicate approval email", ctx do
    {result, _} = stage(ctx)
    count = Repo.aggregate(Hexpm.Emails.OutboxEntry, :count)

    docs =
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar()) |> json_response(201)

    assert docs["id"] == result["id"]
    assert Repo.aggregate(Hexpm.Emails.OutboxEntry, :count) == count
  end

  test "API keys can't revert releases or docs while the organization policy is active", ctx do
    package = insert(:package, name: ctx.name, repository_id: ctx.repository.id)
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    path = "/api/repos/#{ctx.repository.name}/packages/#{ctx.name}/releases/1.0.0"

    for suffix <- ["", "/docs"] do
      build_conn()
      |> put_req_header("authorization", ctx.key.user_secret)
      |> delete(path <> suffix)
      |> response(403)
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
    terminal = read(ctx, result["id"]) |> json_response(200)
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
    staged = StagedReleases.get(result["id"])
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
    assert StagedReleases.get(result["id"]).replace

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases/#{result["id"]}")
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

    staged = StagedReleases.get(result["id"])
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

    assert StagedReleases.get(result["id"]).key_id == ctx.key.id
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

  test "a staged replacement of a public release expires when the release stops being editable",
       ctx do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    package =
      insert(:package,
        require_publish_approval: true,
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
    assert abs(DateTime.diff(StagedReleases.get(result["id"]).expires_at, deadline)) <= 1
  end

  test "an artifact upload failure leaves approval pending for retry", ctx do
    {result, _} = stage(ctx)
    app_env(:hexpm, :repo_bucket, {Hexpm.Store.Mock, "repo_bucket"})
    Mox.stub(Hexpm.Store.Mock, :get_to_file, &Hexpm.Store.Memory.get_to_file/4)
    Mox.expect(Hexpm.Store.Mock, :put_file, fn _, _, _, _ -> raise "store unavailable" end)

    assert_raise RuntimeError, "store unavailable", fn ->
      StagedReleases.approve(result["id"], ctx.user, result["approval_checksum"],
        audit: audit_data(ctx.user)
      )
    end

    assert StagedReleases.get(result["id"])
    assert Repo.exists?(from(l in AuditLog, where: l.action == "release.approve"))
    assert Repo.aggregate(Release, :count) == 1
    assert read(ctx, result["id"]) |> json_response(200) |> Map.fetch!("status") == "staged"

    page =
      build_conn()
      |> test_login(ctx.user)
      |> get("/dashboard/staged-releases/#{result["id"]}")
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
    refute StagedReleases.get(result["id"])
    assert read(ctx, result["id"]) |> json_response(200) |> Map.fetch!("status") == "approved"
  end

  for operation <- [:delete, :delete_data] do
    test "organization #{operation} removes staged artifacts", ctx do
      {result, _} = stage(ctx)
      upload(ctx, "/packages/#{ctx.name}/releases/1.0.0/docs", docs_tar()) |> json_response(201)
      staged = StagedReleases.get(result["id"])

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

  test "API key pages name the packages that require approval", ctx do
    admin = insert(:user_with_tfa)
    organization = ctx.repository.organization
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    organization_user = Repo.preload(organization, :user).user

    package =
      insert(:package, package_owners: [build(:package_owner, user: organization_user)])

    other_package =
      insert(:package,
        require_publish_approval: false,
        package_owners: [build(:package_owner, user: organization_user)]
      )

    for path <- ["/dashboard/keys", "/dashboard/orgs/#{organization.name}/keys"] do
      html = build_conn() |> test_login(admin) |> get(path) |> html_response(200)
      notice = html |> LazyHTML.from_document() |> LazyHTML.query("#publish-approval-packages")
      assert LazyHTML.text(notice) =~ package.name
      refute LazyHTML.text(notice) =~ other_package.name
      assert LazyHTML.text(notice) =~ "stage releases and documentation"
    end
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
    |> post("/dashboard/staged-releases/#{result["id"]}/approve", %{
      checksum: result["approval_checksum"]
    })
  end

  defp read(ctx, id),
    do:
      build_conn()
      |> put_req_header("authorization", ctx.key.user_secret)
      |> get("/api/staged-releases/#{id}")

  defp docs_tar do
    {:ok, body} = :hex_tarball.create_docs([{~c"index.html", "Documentation"}])
    body
  end
end
