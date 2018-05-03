defmodule Hexpm.Billing.ReportTest do
  use Hexpm.DataCase, async: true
  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.Billing
  alias Hexpm.Repository.Repositories

  test "set repository to active" do
    repository1 = insert(:repository, billing_active: true)
    repository2 = insert(:repository, billing_active: true)
    repository3 = insert(:repository, billing_active: false)
    repository4 = insert(:repository, billing_active: false)

    Mox.stub(Billing.Mock, :report, fn ->
      [repository1.name, repository3.name]
    end)

    {:ok, pid} = Billing.Report.start_link(interval: 60_000)
    Sandbox.allow(Repo, self(), pid)
    Mox.allow(Billing.Mock, self(), pid)
    send(pid, :update)
    :sys.get_state(pid)

    assert Repositories.get(repository1.name).billing_active
    refute Repositories.get(repository2.name).billing_active
    assert Repositories.get(repository3.name).billing_active
    refute Repositories.get(repository4.name).billing_active
  end

  test "set repository to unactive" do
    repository1 = insert(:repository, billing_active: true)
    repository2 = insert(:repository, billing_active: true)
    repository3 = insert(:repository, billing_active: false)
    repository4 = insert(:repository, billing_active: false)

    Mox.stub(Billing.Mock, :report, fn -> [] end)

    {:ok, pid} = Billing.Report.start_link(interval: 60_000)
    Sandbox.allow(Repo, self(), pid)
    Mox.allow(Billing.Mock, self(), pid)
    send(pid, :update)
    :sys.get_state(pid)

    refute Repositories.get(repository1.name).billing_active
    refute Repositories.get(repository2.name).billing_active
    refute Repositories.get(repository3.name).billing_active
    refute Repositories.get(repository4.name).billing_active
  end
end
