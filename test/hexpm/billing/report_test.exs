defmodule Hexpm.Billing.ReportTest do
  use Hexpm.DataCase, async: true
  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.Billing
  alias Hexpm.Repository.Repositories

  test "set repository to active" do
    repository1 = insert(:repository, billing_active: true)
    repository2 = insert(:repository, billing_active: false)
    repository3 = insert(:repository, billing_active: false)

    Mox.expect(Billing.Mock, :report, fn ->
      [
        %{"token" => repository1.name, "active" => true},
        %{"token" => repository2.name, "active" => true}
      ]
    end)

    {:ok, pid} = Billing.Report.start_link(timeout: 60_000)
    Sandbox.allow(Repo, self(), pid)
    Mox.allow(Billing.Mock, self(), pid)
    send(pid, :timeout)
    :sys.get_state(pid)

    assert Repositories.get(repository1.name).billing_active
    assert Repositories.get(repository2.name).billing_active
    refute Repositories.get(repository3.name).billing_active
  end

  test "set repository to unactive" do
    repository1 = insert(:repository, billing_active: true)
    repository2 = insert(:repository, billing_active: false)
    repository3 = insert(:repository, billing_active: true)

    Mox.expect(Billing.Mock, :report, fn ->
      [
        %{"token" => repository1.name, "active" => false},
        %{"token" => repository2.name, "active" => false}
      ]
    end)

    {:ok, pid} = Billing.Report.start_link(timeout: 60_000)
    Sandbox.allow(Repo, self(), pid)
    Mox.allow(Billing.Mock, self(), pid)
    send(pid, :timeout)
    :sys.get_state(pid)

    refute Repositories.get(repository1.name).billing_active
    refute Repositories.get(repository2.name).billing_active
    assert Repositories.get(repository3.name).billing_active
  end
end
