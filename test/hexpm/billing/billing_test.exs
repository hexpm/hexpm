defmodule Hexpm.BillingTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.AuditLogs

  describe "cancel/2" do
    test "returns whatever impl().cancel/1 returns" do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn "organization token" -> :whatever end)

      assert Hexpm.Billing.cancel("organization token",
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) == :whatever
    end

    test "creates an Audit Log for billing.cancel" do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn "organization token" -> :whatever end)

      user = insert(:user)

      Hexpm.Billing.cancel("organization token",
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end
  end

  describe "create/2" do
    test "returns {:ok, whatever} when impl().create/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:ok, :whatever} end)

      assert Hexpm.Billing.create(%{},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) ==
               {:ok, :whatever}
    end

    test "creates an Audit Log for billing.create when impl().create/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:ok, %{}} end)

      user = insert(:user)

      Hexpm.Billing.create(%{},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().create/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:error, :reason} end)

      assert Hexpm.Billing.create(%{},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) ==
               {:error, :reason}
    end

    test "does not create an Audit Log when impl().create/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.create(%{},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [] = AuditLogs.all_by(user)
    end
  end

  describe "update/3" do
    test "returns {:ok, whatever} when impl().update/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn "organization token", _params ->
        {:ok, :whatever}
      end)

      assert Hexpm.Billing.update("organization token", %{},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) ==
               {:ok, :whatever}
    end

    test "creates an Audit Log for billing.update when impl().update/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _params -> {:ok, %{}} end)

      user = insert(:user)

      Hexpm.Billing.update("organization token", %{},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().update/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _params -> {:error, :reason} end)

      assert Hexpm.Billing.update("organization token", %{},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) ==
               {:error, :reason}
    end

    test "does not create an Audit Log when impl().update/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _params -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.update("organization token", %{},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [] = AuditLogs.all_by(user)
    end
  end
end
