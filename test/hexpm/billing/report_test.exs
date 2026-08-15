defmodule Hexpm.Billing.ReportTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase
  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.{Billing, RepoBase}
  alias Hexpm.Accounts.Organizations

  setup do
    Mox.set_mox_global()
    Sandbox.mode(RepoBase, {:shared, self()})
    :ok
  end

  test "set organization to active" do
    organization1 = insert(:organization, billing_active: true)
    organization2 = insert(:organization, billing_active: true)
    organization3 = insert(:organization, billing_active: false)
    organization4 = insert(:organization, billing_active: false)

    stub(Billing.Mock, :report, fn ->
      [
        %{"token" => organization1.name, "quantity" => 5},
        %{"token" => organization3.name, "quantity" => 10}
      ]
    end)

    assert :ok = perform_job(Billing.Report, %{})

    assert Organizations.get(organization1.name).billing_active
    refute Organizations.get(organization2.name).billing_active
    assert Organizations.get(organization3.name).billing_active
    refute Organizations.get(organization4.name).billing_active
    # Check seats are updated
    assert Organizations.get(organization1.name).billing_seats == 5
    assert Organizations.get(organization3.name).billing_seats == 10
  end

  test "set organization to inactive" do
    organization1 = insert(:organization, billing_active: true)
    organization2 = insert(:organization, billing_active: true)
    organization3 = insert(:organization, billing_active: false)
    organization4 = insert(:organization, billing_active: false)

    stub(Billing.Mock, :report, fn -> [] end)

    assert :ok = perform_job(Billing.Report, %{})

    refute Organizations.get(organization1.name).billing_active
    refute Organizations.get(organization2.name).billing_active
    refute Organizations.get(organization3.name).billing_active
    refute Organizations.get(organization4.name).billing_active
  end

  test "billing override - empty report" do
    organization1 = insert(:organization, billing_active: true, billing_override: true)
    organization2 = insert(:organization, billing_active: true, billing_override: false)
    organization3 = insert(:organization, billing_active: false, billing_override: true)
    organization4 = insert(:organization, billing_active: false, billing_override: false)

    stub(Billing.Mock, :report, fn -> [] end)

    assert :ok = perform_job(Billing.Report, %{})

    assert Organizations.get(organization1.name).billing_active
    refute Organizations.get(organization2.name).billing_active
    assert Organizations.get(organization3.name).billing_active
    refute Organizations.get(organization4.name).billing_active
  end

  test "billing override - full report" do
    organization1 = insert(:organization, billing_active: true, billing_override: true)
    organization2 = insert(:organization, billing_active: true, billing_override: false)
    organization3 = insert(:organization, billing_active: false, billing_override: true)
    organization4 = insert(:organization, billing_active: false, billing_override: false)

    stub(Billing.Mock, :report, fn ->
      [
        %{"token" => organization1.name, "quantity" => 5},
        %{"token" => organization2.name, "quantity" => 7},
        %{"token" => organization3.name, "quantity" => 8},
        %{"token" => organization4.name, "quantity" => 6}
      ]
    end)

    assert :ok = perform_job(Billing.Report, %{})

    assert Organizations.get(organization1.name).billing_active
    refute Organizations.get(organization2.name).billing_active
    assert Organizations.get(organization3.name).billing_active
    refute Organizations.get(organization4.name).billing_active
    # Check seats are updated
    assert Organizations.get(organization2.name).billing_seats == 7
    assert Organizations.get(organization4.name).billing_seats == 6
  end

  test "revokes excess sessions when seats are reduced via billing report" do
    # Set up organization with 10 seats and 10 active sessions
    organization = insert(:organization, billing_active: true, billing_seats: 10)
    client = insert(:oauth_client)
    expires_at = DateTime.add(DateTime.utc_now(), 30 * 60, :second)

    # Create 10 sessions
    for i <- 1..10 do
      {:ok, _session} =
        Hexpm.UserSessions.create_api_key_session(
          nil,
          organization,
          client.client_id,
          expires_at,
          name: "Session #{i}",
          audit: audit_data(organization.user)
        )
    end

    # Verify we have 10 sessions
    assert Hexpm.UserSessions.count_for_user(organization) == 10

    # Billing report returns reduced seats (10 -> 5)
    stub(Billing.Mock, :report, fn ->
      [%{"token" => organization.name, "quantity" => 5}]
    end)

    assert :ok = perform_job(Billing.Report, %{})

    # Check seats were updated
    updated_org = Organizations.get(organization.name)
    assert updated_org.billing_seats == 5

    # Check excess sessions were revoked (should only have 5 now)
    assert Hexpm.UserSessions.count_for_user(organization) == 5
  end

  test "raises when the billing request fails so Oban retries the job" do
    stub(Billing.Mock, :report, fn -> raise "unavailable" end)

    assert_raise RuntimeError, "unavailable", fn ->
      perform_job(Billing.Report, %{})
    end
  end
end
