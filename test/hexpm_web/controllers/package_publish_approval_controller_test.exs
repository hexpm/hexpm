defmodule HexpmWeb.PackagePublishApprovalControllerTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{Package, StagedReleases}
  alias HexpmWeb.Plugs.Sudo

  setup do
    put_feature_flag(:workload_identity, mode: :enabled)
    user = insert(:user_with_tfa)
    maintainer = insert(:user_with_tfa)

    package =
      insert(:package,
        require_publish_approval: false,
        package_owners: [
          build(:package_owner, user: user),
          build(:package_owner, user: maintainer, level: "maintainer")
        ]
      )
      |> Repo.preload(repository: :organization)

    %{
      user: user,
      maintainer: maintainer,
      package: package,
      path: "/packages/#{package.name}/publish-approval"
    }
  end

  test "full owners enable approval for a package and the change appears in its audit log", ctx do
    assert build_conn() |> test_login(ctx.user) |> post(ctx.path <> "/enable") |> redirected_to() ==
             ctx.path

    assert Repo.get!(Package, ctx.package.id).require_publish_approval
    log = Repo.get_by!(AuditLog, action: "package.publish_approval.configure")
    assert log.params["package"]["id"] == ctx.package.id
    assert log.params["require_publish_approval"]
    assert Enum.any?(Hexpm.Accounts.AuditLogs.all_by(ctx.package), &(&1.id == log.id))

    page = build_conn() |> test_login(ctx.user) |> get(ctx.path) |> html_response(200)
    assert page =~ "Publish approval is enabled for this package"
    assert page =~ "id=\"package-settings-nav\""
    assert page =~ "API key or workload identity"

    audit_page =
      build_conn() |> get("/packages/#{ctx.package.name}/audit-logs") |> html_response(200)

    assert audit_page =~ "Require publish approval"
  end

  test "settings forms and changes require fresh sudo", ctx do
    conn =
      build_conn()
      |> test_login(ctx.user,
        sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

    assert conn |> get(ctx.path) |> redirected_to() == "/sudo"
    assert conn |> post(ctx.path <> "/enable") |> redirected_to() == "/sudo"
    refute Repo.get!(Package, ctx.package.id).require_publish_approval
  end

  test "enabled settings confirm disabling in a modal on the same page", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: true))

    settings =
      build_conn()
      |> test_login(ctx.user)
      |> get(ctx.path)
      |> html_response(200)
      |> LazyHTML.from_document()

    assert settings |> LazyHTML.query("section h2") |> LazyHTML.text() =~ "Publish approval"

    assert settings
           |> LazyHTML.query(~s(#package-settings-nav a[href="#{ctx.path}"] span:last-child))
           |> LazyHTML.text()
           |> String.trim() == "NEW"

    assert settings
           |> LazyHTML.query(~s(section button[type="button"][phx-click]))
           |> LazyHTML.text() =~ "Disable publish approval"

    assert settings |> LazyHTML.query(~s(a[href="#{ctx.path}/disable"])) |> Enum.empty?()

    modal = LazyHTML.query(settings, "#disable-publish-approval-modal")
    assert modal |> LazyHTML.attribute("class") |> hd() =~ "hidden"
    assert modal |> LazyHTML.query(~s([role="dialog"])) |> Enum.count() == 1

    assert LazyHTML.text(modal) =~
             "Publish approval is currently enabled for #{ctx.package.name}."

    assert modal |> LazyHTML.query("strong") |> LazyHTML.text() == ctx.package.name

    assert LazyHTML.text(modal) =~ "Existing staged releases still need approval"

    assert modal
           |> LazyHTML.query(~s(form[action="#{ctx.path}/disable"] button[type="submit"]))
           |> LazyHTML.text() =~ "Disable approval"

    assert modal |> LazyHTML.query(~s(button[type="button"][phx-click])) |> LazyHTML.text() =~
             "Cancel"
  end

  test "disabled settings have an enable form and no disable modal", ctx do
    page =
      build_conn()
      |> test_login(ctx.user)
      |> get(ctx.path)
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ "Publish approval is disabled for this package."
    assert page |> LazyHTML.query("#disable-publish-approval-modal") |> Enum.empty?()
    assert page |> LazyHTML.query(~s(form[action="#{ctx.path}/disable"])) |> Enum.empty?()
    assert page |> LazyHTML.query(~s(form[action="#{ctx.path}/enable"])) |> Enum.count() == 1
  end

  test "a token from enabling can't authorize disabling", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: true))

    conn =
      build_conn()
      |> test_login(ctx.user,
        sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

    token = Sudo.generate_form_token(ctx.user.id, "POST", ctx.path <> "/enable")
    assert conn |> get(ctx.path) |> redirected_to() == "/sudo"

    assert conn |> post(ctx.path <> "/disable", %{_sudo_token: token}) |> redirected_to() ==
             "/sudo"

    assert Repo.get!(Package, ctx.package.id).require_publish_approval
  end

  test "disabling is audited and notifies full owners and owning organization admins", ctx do
    other = insert(:user)
    insert(:package_owner, package: ctx.package, user: other)
    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:package_owner, package: ctx.package, user: organization.user)
    Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: true))

    assert build_conn() |> test_login(ctx.user) |> post(ctx.path <> "/disable") |> redirected_to() ==
             ctx.path

    refute Repo.get!(Package, ctx.package.id).require_publish_approval

    refute Repo.get_by!(AuditLog, action: "package.publish_approval.configure").params[
             "require_publish_approval"
           ]

    email =
      Repo.one!(
        from(e in Hexpm.Emails.OutboxEntry, where: e.category == "publish_approval.disabled")
      )

    assert Enum.sort(email.recipients) ==
             Enum.sort(
               Enum.map([ctx.user, other, admin], &Hexpm.Accounts.User.email(&1, :primary))
             )

    assert email.email["text_body"] =~ ctx.package.name

    assert email.email["text_body"] =~
             "Organization and registry policies may still require approval"

    audit_page =
      build_conn() |> get("/packages/#{ctx.package.name}/audit-logs") |> html_response(200)

    assert audit_page =~ "Disable publish approval"
  end

  test "maintainers can view the setting but can't change it", ctx do
    conn = build_conn() |> test_login(ctx.maintainer)
    page = conn |> get(ctx.path) |> html_response(200)
    refute page =~ ctx.path <> "/enable"
    conn |> post(ctx.path <> "/enable") |> response(403)
    conn |> post(ctx.path <> "/disable") |> response(403)
    refute Repo.get!(Package, ctx.package.id).require_publish_approval
  end

  test "non-owners can't view or change the setting", ctx do
    conn = build_conn() |> test_login(insert(:user_with_tfa))
    conn |> get(ctx.path) |> response(403)
    conn |> post(ctx.path <> "/enable") |> response(403)
  end

  test "full owners need enrolled 2FA to change the setting", ctx do
    user = insert(:user)
    insert(:package_owner, package: ctx.package, user: user)
    build_conn() |> test_login(user) |> post(ctx.path <> "/enable") |> response(403)
    refute Repo.get!(Package, ctx.package.id).require_publish_approval
  end

  test "the setting is unavailable outside the staging rollout", ctx do
    put_feature_flag(:workload_identity, mode: :off)
    conn = build_conn() |> test_login(ctx.user)
    conn |> get(ctx.path) |> response(404)
    conn |> post(ctx.path <> "/enable") |> response(404)

    assert {:error, :forbidden} =
             StagedReleases.configure(ctx.package, ctx.user, true,
               audit: test_audit_data(ctx.user)
             )
  end

  test "the context rechecks the current full ownership", ctx do
    owner =
      Repo.get_by!(Hexpm.Repository.PackageOwner,
        package_id: ctx.package.id,
        user_id: ctx.user.id
      )

    Repo.update!(Ecto.Changeset.change(owner, level: "maintainer"))

    assert {:error, :forbidden} =
             StagedReleases.configure(ctx.package, ctx.user, true,
               audit: test_audit_data(ctx.user)
             )

    refute Repo.get!(Package, ctx.package.id).require_publish_approval
  end

  test "private repository admins manage package approval and organization requirements still apply",
       ctx do
    repository =
      insert(:repository, organization: build(:organization, require_publish_approval: true))

    insert(:organization_user,
      organization: repository.organization,
      user: ctx.user,
      role: "admin"
    )

    insert(:organization_user,
      organization: repository.organization,
      user: ctx.maintainer,
      role: "write"
    )

    package = insert(:package, repository_id: repository.id, require_publish_approval: false)
    path = "/packages/#{repository.name}/#{package.name}/publish-approval"

    page = build_conn() |> test_login(ctx.user) |> get(path) |> html_response(200)
    assert page =~ "Your organization requires approval"

    assert build_conn() |> test_login(ctx.user) |> post(path <> "/enable") |> redirected_to() ==
             path

    assert build_conn() |> test_login(ctx.user) |> post(path <> "/disable") |> redirected_to() ==
             path

    refute Repo.get!(Package, package.id).require_publish_approval
    key = insert(:key, user: ctx.user)

    assert StagedReleases.required?(repository, Repo.get!(Package, package.id), %{
             user: ctx.user,
             auth_credential: key
           })

    build_conn() |> test_login(ctx.maintainer) |> post(path <> "/enable") |> response(403)
  end
end
