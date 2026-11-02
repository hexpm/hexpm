defmodule HexpmWeb.Dashboard.InvitationControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.{OrganizationInvitation, OrganizationInvitations, Organizations}

  setup do
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    user = insert(:user)

    {:ok, invitation} =
      OrganizationInvitations.invite_user(organization, user, %{"role" => "write"}, admin,
        audit: audit_data(admin)
      )

    %{organization: organization, admin: admin, user: user, invitation: invitation}
  end

  describe "GET /dashboard/invitations" do
    test "lists the account's pending invitations", %{
      organization: organization,
      admin: admin,
      user: user,
      invitation: invitation
    } do
      html =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/invitations")
        |> html_response(200)

      assert html =~ organization.name

      [details] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#invitation-#{invitation.id} p.text-xs")
        |> Enum.to_list()

      assert details |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim() =~
               "Invited by #{admin.username} as write, expires"

      assert details |> LazyHTML.query("strong") |> LazyHTML.text() |> String.trim() ==
               admin.username
    end

    test "shows the invitation in the sidebar of other dashboard pages", %{
      organization: organization,
      user: user
    } do
      html =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/profile")
        |> html_response(200)

      assert html =~ ~s(href="/dashboard/invitations")
      assert html =~ organization.name
    end

    test "does not list invitations for other accounts", %{invitation: invitation} do
      html =
        build_conn()
        |> test_login(insert(:user))
        |> get("/dashboard/invitations")
        |> html_response(200)

      assert html =~ "You have no pending invitations."
      refute html =~ ~s(id="invitation-#{invitation.id}")
      assert html =~ ~s(href="/dashboard/invitations")
    end
  end

  describe "POST /dashboard/invitations/:organization/accept" do
    test "joins the organization", %{organization: organization, user: user} do
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/#{organization.name}/accept")

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "You have joined the #{organization.name} organization."

      assert Organizations.get_role(organization, user) == "write"
    end

    test "refuses an account the invitation isn't for", %{
      organization: organization,
      user: user
    } do
      other = insert(:user)

      conn =
        build_conn()
        |> test_login(other)
        |> post("/dashboard/invitations/#{organization.name}/accept")

      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This invitation is no longer valid."

      refute Organizations.get_role(organization, other)
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "keeps the invitation when the organization has no seat left", %{
      organization: organization,
      user: user
    } do
      seats(organization, 1)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/#{organization.name}/accept")

      assert html_response(conn, 400)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "#{organization.name} has no seats left. Ask an administrator to add one and try again."

      refute Organizations.get_role(organization, user)
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "answers an unknown organization as an invalid invitation", %{user: user} do
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/not_an_organization/accept")

      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This invitation is no longer valid."
    end
  end

  describe "POST /dashboard/invitations/:organization/decline" do
    test "declines the invitation", %{
      organization: organization,
      admin: admin,
      user: user,
      invitation: invitation
    } do
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/#{organization.name}/decline")

      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "You declined the invitation to #{organization.name}."

      assert Repo.get!(OrganizationInvitation, invitation.id).declined_at
      assert OrganizationInvitations.all_pending_for_user(user) == []

      assert {:error, :invitation_cooldown} =
               OrganizationInvitations.invite_user(organization, user, %{"role" => "read"}, admin,
                 audit: audit_data(admin)
               )
    end

    test "refuses an account the invitation isn't for", %{
      organization: organization,
      user: user,
      invitation: invitation
    } do
      conn =
        build_conn()
        |> test_login(insert(:user))
        |> post("/dashboard/invitations/#{organization.name}/decline")

      assert redirected_to(conn) == "/dashboard/invitations"
      refute Repo.get!(OrganizationInvitation, invitation.id).declined_at
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end
  end

  test "declined invitations have a persistent undo action", %{
    organization: organization,
    user: user,
    invitation: invitation
  } do
    conn =
      build_conn()
      |> test_login(user)
      |> post("/dashboard/invitations/#{organization.name}/decline")

    html = conn |> recycle() |> get("/dashboard/invitations") |> html_response(200)
    assert html =~ ~s(action="/dashboard/invitations/#{organization.name}/restore")
    assert html =~ "Undo decline"

    conn = conn |> recycle() |> post("/dashboard/invitations/#{organization.name}/restore")
    assert redirected_to(conn) == "/dashboard/invitations"
    assert [%{id: id}] = OrganizationInvitations.all_pending_for_user(user)
    assert id == invitation.id
  end

  test "restores the declined invitation when the organization revoked an earlier one", %{
    organization: organization,
    admin: admin,
    user: user,
    invitation: invitation
  } do
    {:ok, _revoked} =
      OrganizationInvitations.revoke(organization, invitation, audit: audit_data(admin))

    invitation
    |> Ecto.Changeset.change(sent_at: DateTime.add(DateTime.utc_now(), -2, :day))
    |> Repo.update!()

    {:ok, reissued} =
      OrganizationInvitations.invite_user(organization, user, %{"role" => "read"}, admin,
        audit: audit_data(admin)
      )

    {:ok, _declined} = OrganizationInvitations.decline(reissued, user, audit: audit_data(user))

    conn =
      build_conn()
      |> test_login(user)
      |> post("/dashboard/invitations/#{organization.name}/restore")

    assert redirected_to(conn) == "/dashboard/invitations"

    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "You restored the invitation to #{organization.name}."

    assert [%{id: id}] = OrganizationInvitations.all_pending_for_user(user)
    assert id == reissued.id
    assert Repo.get!(OrganizationInvitation, invitation.id).revoked_at
  end

  test "blocks and unblocks from the invitations settings page", %{
    user: user,
    admin: admin,
    organization: organization
  } do
    conn =
      build_conn()
      |> test_login(user)
      |> post("/dashboard/invitations/#{organization.name}/block")

    assert redirected_to(conn) == "/dashboard/invitations"
    assert [_block] = OrganizationInvitations.all_blocks_for_user(user)

    assert {:error, :blocked} =
             OrganizationInvitations.invite_user(organization, user, %{"role" => "read"}, admin,
               audit: audit_data(admin)
             )

    html = conn |> recycle() |> get("/dashboard/invitations") |> html_response(200)
    assert html =~ "Declined and blocked organizations"
    assert html =~ ~s(action="/dashboard/invitations/blocks/#{organization.name}/unblock")
    refute html =~ ~s(action="/dashboard/invitations/#{organization.name}/restore")

    conn = conn |> recycle() |> post("/dashboard/invitations/blocks/#{organization.name}/unblock")
    assert redirected_to(conn) == "/dashboard/invitations"
    assert OrganizationInvitations.all_blocks_for_user(user) == []
    assert OrganizationInvitations.all_pending_for_user(user) == []
    html = conn |> recycle() |> get("/dashboard/invitations") |> html_response(200)
    assert html =~ ~s(action="/dashboard/invitations/#{organization.name}/restore")
  end

  test "another account can't restore, block, or unblock", %{
    user: user,
    invitation: invitation,
    organization: organization
  } do
    {:ok, _declined} = OrganizationInvitations.decline(invitation, user, audit: audit_data(user))
    other = insert(:user)

    for action <- ["restore", "block"] do
      conn =
        build_conn()
        |> test_login(other)
        |> post("/dashboard/invitations/#{organization.name}/#{action}")

      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This invitation is no longer valid."
    end

    assert {:ok, _invitation} =
             OrganizationInvitations.block(invitation, user, audit: audit_data(user))

    assert [_block] = OrganizationInvitations.all_blocks_for_user(user)

    conn =
      build_conn()
      |> test_login(other)
      |> post("/dashboard/invitations/blocks/#{organization.name}/unblock")

    assert redirected_to(conn) == "/dashboard/invitations"
    assert [_block] = OrganizationInvitations.all_blocks_for_user(user)

    html =
      build_conn() |> test_login(other) |> get("/dashboard/invitations") |> html_response(200)

    refute html =~ ~s(id="organization-invitation-state-#{organization.id}")
    refute html =~ ~s(id="declined-and-blocked-organizations")
  end

  test "combines declined and blocked organizations without duplicate rows", %{
    user: user,
    invitation: invitation,
    organization: organization,
    admin: admin
  } do
    {:ok, _declined} = OrganizationInvitations.decline(invitation, user, audit: audit_data(user))
    blocked_org = insert(:organization)

    {:ok, blocked_invitation} =
      OrganizationInvitations.invite_user(blocked_org, user, %{"role" => "read"}, admin,
        audit: audit_data(admin)
      )

    {:ok, _blocked} =
      OrganizationInvitations.block(blocked_invitation, user, audit: audit_data(user))

    [_block] = OrganizationInvitations.all_blocks_for_user(user)

    html = build_conn() |> test_login(user) |> get("/dashboard/invitations") |> html_response(200)
    document = LazyHTML.from_document(html)

    assert Enum.count(LazyHTML.query(document, "#declined-and-blocked-organizations tbody tr")) ==
             2

    [declined_row] =
      LazyHTML.query(document, "#organization-invitation-state-#{organization.id}")
      |> Enum.to_list()

    assert LazyHTML.text(declined_row) =~ "Declined"
    assert LazyHTML.text(declined_row) =~ Calendar.strftime(invitation.expires_at, "%Y-%m-%d")

    assert Enum.count(
             LazyHTML.query(
               declined_row,
               ~s(form[action="/dashboard/invitations/#{organization.name}/restore"])
             )
           ) == 1

    assert Enum.count(
             LazyHTML.query(
               declined_row,
               ~s(form[action="/dashboard/invitations/#{organization.name}/block"])
             )
           ) == 1

    [blocked_row] =
      LazyHTML.query(document, "#organization-invitation-state-#{blocked_org.id}")
      |> Enum.to_list()

    assert LazyHTML.text(blocked_row) =~ "Blocked"

    assert Enum.count(
             LazyHTML.query(
               blocked_row,
               ~s(form[action="/dashboard/invitations/blocks/#{blocked_org.name}/unblock"])
             )
           ) == 1

    assert Enum.empty?(
             LazyHTML.query(
               blocked_row,
               ~s(form[action="/dashboard/invitations/#{blocked_org.name}/restore"])
             )
           )

    assert Enum.empty?(
             LazyHTML.query(
               blocked_row,
               ~s(form[action="/dashboard/invitations/#{blocked_org.name}/block"])
             )
           )
  end

  test "unblocking changes the same row to declined while the invitation is valid", %{
    user: user,
    invitation: invitation,
    organization: organization
  } do
    {:ok, _blocked} = OrganizationInvitations.block(invitation, user, audit: audit_data(user))
    [_block] = OrganizationInvitations.all_blocks_for_user(user)

    conn =
      build_conn()
      |> test_login(user)
      |> post("/dashboard/invitations/blocks/#{organization.name}/unblock")

    html = conn |> recycle() |> get("/dashboard/invitations") |> html_response(200)
    document = LazyHTML.from_document(html)

    [row] =
      LazyHTML.query(document, "#organization-invitation-state-#{organization.id}")
      |> Enum.to_list()

    assert LazyHTML.text(row) =~ "Declined"
    refute LazyHTML.text(row) =~ "Unblock"

    assert Enum.count(
             LazyHTML.query(
               row,
               ~s(form[action="/dashboard/invitations/#{organization.name}/restore"])
             )
           ) == 1
  end

  test "an expired invitation leaves a blocked row until it is unblocked", %{
    user: user,
    invitation: invitation,
    organization: organization
  } do
    {:ok, _blocked} = OrganizationInvitations.block(invitation, user, audit: audit_data(user))
    [_block] = OrganizationInvitations.all_blocks_for_user(user)

    invitation
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    conn = build_conn() |> test_login(user) |> get("/dashboard/invitations")
    html = html_response(conn, 200)
    assert html =~ ~s(id="organization-invitation-state-#{organization.id}")
    assert html =~ ~s(action="/dashboard/invitations/blocks/#{organization.name}/unblock")

    conn = conn |> recycle() |> post("/dashboard/invitations/blocks/#{organization.name}/unblock")
    html = conn |> recycle() |> get("/dashboard/invitations") |> html_response(200)
    refute html =~ ~s(id="declined-and-blocked-organizations")
    refute html =~ ~s(id="organization-invitation-state-#{organization.id}")
  end

  test "organizations without an invitation or block don't change invitation state", %{
    user: user
  } do
    for name <- ["not_an_organization", insert(:organization).name],
        path <- [
          "/dashboard/invitations/#{name}/accept",
          "/dashboard/invitations/#{name}/decline",
          "/dashboard/invitations/#{name}/restore",
          "/dashboard/invitations/#{name}/block",
          "/dashboard/invitations/blocks/#{name}/unblock"
        ] do
      conn = build_conn() |> test_login(user) |> post(path)
      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This invitation is no longer valid."
    end

    assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    assert OrganizationInvitations.all_blocks_for_user(user) == []
  end
end
