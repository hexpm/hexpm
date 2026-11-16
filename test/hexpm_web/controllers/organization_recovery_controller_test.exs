defmodule HexpmWeb.OrganizationRecoveryControllerTest do
  use HexpmWeb.ConnCase, async: true

  import Mox

  alias Hexpm.Accounts.{OrganizationRecoveries, OrganizationRecovery}

  setup :verify_on_exit!

  setup do
    organization = insert(:organization, billing_seats: 2)
    old_admin = insert(:user)
    insert(:organization_user, organization: organization, user: old_admin, role: "admin")
    new_admin = insert(:user)

    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts ->
      %{"email" => "billing@example.com"}
    end)

    expect(Hexpm.Billing.Mock, :create_payment_verification, fn _name ->
      {:ok, %{"brand" => "visa", "last4" => "4242"}}
    end)

    {:ok, recovery} = OrganizationRecoveries.start(organization, new_admin, nil)

    %{organization: organization, new_admin: new_admin, recovery: recovery}
  end

  test "sends an anonymous visitor to log in first", %{recovery: recovery} do
    conn = get(build_conn(), "/organization-recovery?token=#{recovery.raw_token}")

    assert redirected_to(conn) =~ "/login"
  end

  test "asks the named account for the statement code", c do
    conn =
      build_conn()
      |> test_login(c.new_admin)
      |> get("/organization-recovery?token=#{c.recovery.raw_token}")

    html = html_response(conn, 200)
    assert html =~ c.organization.name
    assert html =~ "visa card ending in 4242"
    assert html =~ "Statement code"
  end

  test "turns away any other account", %{recovery: recovery} do
    conn =
      build_conn()
      |> test_login(insert(:user))
      |> get("/organization-recovery?token=#{recovery.raw_token}")

    assert redirected_to(conn) == "/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no longer valid"
  end

  test "turns away an unknown token", %{new_admin: new_admin} do
    conn =
      build_conn()
      |> test_login(new_admin)
      |> get("/organization-recovery?token=unknown")

    assert redirected_to(conn) == "/dashboard"
  end

  test "confirms the right code", c do
    name = c.organization.name
    expect(Hexpm.Billing.Mock, :verify_payment, fn ^name, "ABC123" -> :ok end)

    conn =
      build_conn()
      |> test_login(c.new_admin)
      |> post("/organization-recovery?token=#{c.recovery.raw_token}", %{"code" => "ABC123"})

    html = html_response(conn, 200)
    assert html =~ "The code has been confirmed"
    assert Repo.get!(OrganizationRecovery, c.recovery.id).verified_at
  end

  test "explains a wrong code", c do
    expect(Hexpm.Billing.Mock, :verify_payment, fn _name, "WRONG1" ->
      {:error, %{"errors" => %{"code" => "invalid"}}}
    end)

    conn =
      build_conn()
      |> test_login(c.new_admin)
      |> post("/organization-recovery?token=#{c.recovery.raw_token}", %{"code" => "WRONG1"})

    assert html_response(conn, 400) =~ "Statement code"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't match"

    refute Repo.get!(OrganizationRecovery, c.recovery.id).verified_at
  end
end
