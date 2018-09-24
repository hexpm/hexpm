defmodule Hexpm.Billing.ReportTest do
  use Hexpm.DataCase, async: true
  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.{Billing, RepoBase}
  alias Hexpm.Accounts.Organizations

  test "set organization to active" do
    organization1 = insert(:organization, billing_active: true)
    organization2 = insert(:organization, billing_active: true)
    organization3 = insert(:organization, billing_active: false)
    organization4 = insert(:organization, billing_active: false)

    Mox.stub(Billing.Mock, :report, fn ->
      [organization1.name, organization3.name]
    end)

    {:ok, pid} = Billing.Report.start_link(interval: 60_000)
    Sandbox.allow(RepoBase, self(), pid)
    Mox.allow(Billing.Mock, self(), pid)
    send(pid, :update)
    :sys.get_state(pid)

    assert Organizations.get(organization1.name).billing_active
    refute Organizations.get(organization2.name).billing_active
    assert Organizations.get(organization3.name).billing_active
    refute Organizations.get(organization4.name).billing_active
  end

  test "set organization to inactive" do
    organization1 = insert(:organization, billing_active: true)
    organization2 = insert(:organization, billing_active: true)
    organization3 = insert(:organization, billing_active: false)
    organization4 = insert(:organization, billing_active: false)

    Mox.stub(Billing.Mock, :report, fn -> [] end)

    {:ok, pid} = Billing.Report.start_link(interval: 60_000)
    Sandbox.allow(RepoBase, self(), pid)
    Mox.allow(Billing.Mock, self(), pid)
    send(pid, :update)
    :sys.get_state(pid)

    refute Organizations.get(organization1.name).billing_active
    refute Organizations.get(organization2.name).billing_active
    refute Organizations.get(organization3.name).billing_active
    refute Organizations.get(organization4.name).billing_active
  end
end
