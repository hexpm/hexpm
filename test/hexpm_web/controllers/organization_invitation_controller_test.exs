defmodule HexpmWeb.OrganizationInvitationControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.{OrganizationInvitations, Organizations}

  setup do
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    {:ok, invitation} =
      OrganizationInvitations.invite(
        organization,
        %{"email" => "newcomer@example.com", "role" => "write"},
        admin,
        audit: audit_data(admin)
      )

    %{organization: organization, admin: admin, invitation: invitation}
  end

  test "sends an anonymous visitor to log in first", %{invitation: invitation} do
    conn = get(build_conn(), "/invites/#{invitation.raw_token}")

    assert redirected_to(conn) =~ "/login"
  end

  test "shows what accepting will do", %{invitation: invitation} do
    newcomer = insert(:user)

    conn =
      build_conn()
      |> test_login(newcomer)
      |> get("/invites/#{invitation.raw_token}")

    html = html_response(conn, 200)
    assert html =~ invitation.organization.name
    assert html =~ newcomer.username
    assert html =~ "write"
  end

  test "joins the signed-in account", %{organization: organization, invitation: invitation} do
    newcomer = insert(:user)

    conn =
      build_conn()
      |> test_login(newcomer)
      |> post("/invites/#{invitation.raw_token}")

    assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
    assert Organizations.get_role(organization, newcomer) == "write"
  end

  test "refuses a token that has already been used", %{invitation: invitation} do
    build_conn() |> test_login(insert(:user)) |> post("/invites/#{invitation.raw_token}")

    conn =
      build_conn()
      |> test_login(insert(:user))
      |> post("/invites/#{invitation.raw_token}")

    assert redirected_to(conn) == "/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no longer valid"
  end

  test "refuses a token that was never issued" do
    conn =
      build_conn()
      |> test_login(insert(:user))
      |> get("/invites/nonsense")

    assert redirected_to(conn) == "/dashboard"
  end

  test "says so when the organization has no seat left", %{admin: admin} do
    organization = insert(:organization, billing_seats: 1)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    {:ok, invitation} =
      OrganizationInvitations.invite(
        organization,
        %{"email" => "newcomer@example.com", "role" => "read"},
        admin,
        audit: audit_data(admin)
      )

    conn =
      build_conn()
      |> test_login(insert(:user))
      |> post("/invites/#{invitation.raw_token}")

    assert html_response(conn, 400)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no seats left"
  end
end
