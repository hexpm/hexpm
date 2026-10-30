defmodule HexpmWeb.PublishApprovalControllerTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Repository.StagedReleases
  alias HexpmWeb.Plugs.Sudo

  setup do
    put_feature_flag(:workload_identity, mode: :enabled)
    user = insert(:user_with_tfa)
    repository = insert(:repository)
    organization = repository.organization
    insert(:organization_user, organization: organization, user: user, role: "admin")

    %{
      user: user,
      repository: repository,
      organization: organization,
      path: "/dashboard/orgs/#{organization.name}/publish-approval"
    }
  end

  test "an admin enables the policy and the change is audited", ctx do
    conn = build_conn() |> test_login(ctx.user) |> post(ctx.path <> "/enable")
    assert redirected_to(conn) == ctx.path
    assert Repo.get!(Hexpm.Accounts.Organization, ctx.organization.id).require_publish_approval
    log = Repo.get_by!(Hexpm.Accounts.AuditLog, action: "organization.publish_approval.configure")
    assert log.params["require_publish_approval"]
  end

  test "enabled settings retain organization navigation and confirm disabling in a modal", ctx do
    {:ok, _} =
      StagedReleases.configure(ctx.organization, ctx.user, true, audit: test_audit_data(ctx.user))

    settings =
      build_conn()
      |> test_login(ctx.user)
      |> get(ctx.path)
      |> html_response(200)
      |> LazyHTML.from_document()

    assert settings |> LazyHTML.query("section h2") |> LazyHTML.text() =~ "Publish approval"

    assert settings
           |> LazyHTML.query(~s(#org-nav a[href="#{ctx.path}"] span:last-child))
           |> LazyHTML.text()
           |> String.trim() == "NEW"

    assert settings
           |> LazyHTML.query(~s(#org-nav a[data-active="true"]))
           |> LazyHTML.attribute("href") == [ctx.path]

    assert settings
           |> LazyHTML.query(~s(section button[type="button"][phx-click]))
           |> LazyHTML.text() =~ "Disable publish approval"

    assert settings |> LazyHTML.query(~s(a[href="#{ctx.path}/disable"])) |> Enum.empty?()

    modal = LazyHTML.query(settings, "#disable-publish-approval-modal")
    assert modal |> LazyHTML.attribute("class") |> hd() =~ "hidden"
    assert modal |> LazyHTML.query(~s([role="dialog"])) |> Enum.count() == 1

    assert LazyHTML.text(modal) =~
             "Publish approval is currently enabled for #{ctx.organization.name}."

    assert LazyHTML.text(modal) =~ "Existing staged releases still need approval"

    assert modal
           |> LazyHTML.query(~s(form[action="#{ctx.path}/disable"] button[type="submit"]))
           |> LazyHTML.text() =~ "Disable approval"

    assert modal |> LazyHTML.query(~s(button[type="button"][phx-click])) |> LazyHTML.text() =~
             "Cancel"
  end

  test "disabled settings retain rolling sudo and don't issue a disable modal or token", ctx do
    page =
      build_conn()
      |> test_login(ctx.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60))
      |> get(ctx.path)
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(page) =~ "Publish approval is disabled."
    assert page |> LazyHTML.query("#disable-publish-approval-modal") |> Enum.empty?()
    assert page |> LazyHTML.query(~s(form[action="#{ctx.path}/disable"])) |> Enum.empty?()
    assert page |> LazyHTML.query(~s(form[action="#{ctx.path}/enable"])) |> Enum.count() == 1
  end

  test "a disable token from the freshly verified settings page survives the fresh-sudo window",
       ctx do
    {:ok, _} =
      StagedReleases.configure(ctx.organization, ctx.user, true, audit: test_audit_data(ctx.user))

    settings =
      build_conn()
      |> test_login(ctx.user)
      |> get(ctx.path)
      |> html_response(200)
      |> LazyHTML.from_document()

    [token] =
      settings
      |> LazyHTML.query(
        ~s(#disable-publish-approval-modal form[action="#{ctx.path}/disable"] input[name="_sudo_token"])
      )
      |> LazyHTML.attribute("value")

    conn =
      build_conn()
      |> test_login(ctx.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60))
      |> post(ctx.path <> "/disable", %{_sudo_token: token})

    assert redirected_to(conn) == ctx.path
    refute Repo.get!(Hexpm.Accounts.Organization, ctx.organization.id).require_publish_approval
  end

  test "disabling requires forced sudo and an enable form token can't bypass it", ctx do
    {:ok, _} =
      StagedReleases.configure(ctx.organization, ctx.user, true, audit: test_audit_data(ctx.user))

    conn =
      build_conn()
      |> test_login(ctx.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60))

    assert conn |> get(ctx.path) |> redirected_to() == "/sudo"
    token = Sudo.generate_form_token(ctx.user.id, "POST", ctx.path <> "/enable")

    assert conn |> post(ctx.path <> "/disable", %{_sudo_token: token}) |> redirected_to() ==
             "/sudo"

    assert Repo.get!(Hexpm.Accounts.Organization, ctx.organization.id).require_publish_approval
  end

  test "disabling sends every administrator a durable notification", ctx do
    second = insert(:user)
    insert(:organization_user, organization: ctx.organization, user: second, role: "admin")

    {:ok, _} =
      StagedReleases.configure(ctx.organization, ctx.user, true, audit: test_audit_data(ctx.user))

    conn = build_conn() |> test_login(ctx.user)
    assert conn |> get(ctx.path) |> html_response(200) =~ "Every administrator"
    assert conn |> post(ctx.path <> "/disable") |> redirected_to() == ctx.path
    refute Repo.get!(Hexpm.Accounts.Organization, ctx.organization.id).require_publish_approval

    email =
      Repo.one!(
        from(e in Hexpm.Emails.OutboxEntry, where: e.category == "staged-publishing-policy")
      )

    assert Enum.sort(email.recipients) ==
             Enum.sort([
               Hexpm.Accounts.User.email(ctx.user, :primary),
               Hexpm.Accounts.User.email(second, :primary)
             ])
  end

  test "the organization setting is hidden and inaccessible outside the rollout", ctx do
    put_feature_flag(:workload_identity, mode: :off)
    build_conn() |> test_login(ctx.user) |> get(ctx.path) |> response(404)
    build_conn() |> test_login(ctx.user) |> post(ctx.path <> "/enable") |> response(404)
    refute Repo.get!(Hexpm.Accounts.Organization, ctx.organization.id).require_publish_approval
  end

  test "an administrator needs 2FA to configure publish approval", ctx do
    user = insert(:user)
    insert(:organization_user, organization: ctx.organization, user: user, role: "admin")
    build_conn() |> test_login(user) |> post(ctx.path <> "/enable") |> response(403)
    refute Repo.get!(Hexpm.Accounts.Organization, ctx.organization.id).require_publish_approval
  end

  test "writers can't configure the organization policy", ctx do
    user = insert(:user_with_tfa)
    insert(:organization_user, organization: ctx.organization, user: user, role: "write")
    build_conn() |> test_login(user) |> post(ctx.path <> "/enable") |> response(404)
  end
end
