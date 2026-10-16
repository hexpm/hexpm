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
      user: user
    } do
      html =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/invitations")
        |> html_response(200)

      assert html =~ organization.name
      assert html =~ "Invited by #{admin.username} as write"
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
      refute html =~ ~s(href="/dashboard/invitations")
    end
  end

  describe "POST /dashboard/invitations/:id/accept" do
    test "joins the organization", %{
      organization: organization,
      user: user,
      invitation: invitation
    } do
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/#{invitation.id}/accept")

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "You have joined the #{organization.name} organization."

      assert Organizations.get_role(organization, user) == "write"
    end

    test "refuses an account the invitation isn't for", %{
      organization: organization,
      user: user,
      invitation: invitation
    } do
      other = insert(:user)

      conn =
        build_conn()
        |> test_login(other)
        |> post("/dashboard/invitations/#{invitation.id}/accept")

      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This invitation is no longer valid."

      refute Organizations.get_role(organization, other)
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "keeps the invitation when the organization has no seat left", %{
      organization: organization,
      user: user,
      invitation: invitation
    } do
      seats(organization, 1)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/#{invitation.id}/accept")

      assert html_response(conn, 400)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "#{organization.name} has no seats left. Ask an administrator to add one and try again."

      refute Organizations.get_role(organization, user)
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "answers an unknown id as an invalid invitation", %{user: user} do
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/not-an-id/accept")

      assert redirected_to(conn) == "/dashboard/invitations"
    end
  end

  describe "POST /dashboard/invitations/:id/decline" do
    test "declines the invitation", %{
      organization: organization,
      admin: admin,
      user: user,
      invitation: invitation
    } do
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/invitations/#{invitation.id}/decline")

      assert redirected_to(conn) == "/dashboard/invitations"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "You declined the invitation to #{organization.name}."

      assert Repo.get!(OrganizationInvitation, invitation.id).declined_at
      assert OrganizationInvitations.all_pending_for_user(user) == []

      assert {:error, :declined} =
               OrganizationInvitations.invite_user(organization, user, %{"role" => "read"}, admin,
                 audit: audit_data(admin)
               )
    end

    test "refuses an account the invitation isn't for", %{user: user, invitation: invitation} do
      conn =
        build_conn()
        |> test_login(insert(:user))
        |> post("/dashboard/invitations/#{invitation.id}/decline")

      assert redirected_to(conn) == "/dashboard/invitations"
      refute Repo.get!(OrganizationInvitation, invitation.id).declined_at
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end
  end
end
