defmodule Hexpm.BillingTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.AuditLogs

  describe "complete_session/4" do
    test "returns {:ok, whatever} when impl().complete_session/3 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :complete_session, fn "name", "SESSION_ID", "127.0.0.1" ->
        :ok
      end)

      assert Hexpm.Billing.complete_session("name", "SESSION_ID", "127.0.0.1",
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) == :ok
    end

    test "creates an Audit Log when impl().complete_session/3 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :complete_session, fn _, _, _ -> :ok end)

      user = insert(:user)

      Hexpm.Billing.complete_session("name", "SESSION_ID", "127.0.0.1",
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().complete_session/3 fails" do
      Mox.stub(Hexpm.Billing.Mock, :complete_session, fn "name", "SESSION_ID", "127.0.0.1" ->
        {:error, :reason}
      end)

      assert Hexpm.Billing.complete_session("name", "SESSION_ID", "127.0.0.1",
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) == {:error, :reason}
    end

    test "does not create an Audit Log when impl().complete_session/3 fails" do
      Mox.stub(Hexpm.Billing.Mock, :complete_session, fn _, _, _ -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.complete_session("name", "SESSION_ID", "127.0.0.1",
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [] == AuditLogs.all_by(user)
    end
  end

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

  describe "change_plan/3" do
    test "returns :ok when impl().change_plan/2 returns :ok" do
      Mox.stub(Hexpm.Billing.Mock, :change_plan, fn "organization token",
                                                    %{"plan_id" => "new_plan"} ->
        :ok
      end)

      assert Hexpm.Billing.change_plan("organization token", %{"plan_id" => "new_plan"},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) == :ok
    end

    test "creates an Audit Log for billing.change_plan" do
      Mox.stub(Hexpm.Billing.Mock, :change_plan, fn _, _ -> :ok end)

      user = insert(:user)

      Hexpm.Billing.change_plan("organization token", %{"plan_id" => "new_plan"},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end
  end

  describe "pay_invoice/2" do
    test "returns :ok when impl().pay_invoice/1 returns :ok" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn 238 -> :ok end)

      assert Hexpm.Billing.pay_invoice(238,
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) == :ok
    end

    test "creates an Audit Log for pay_invoice whn imp().pay_invoice/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _ -> :ok end)

      user = insert(:user)

      Hexpm.Billing.pay_invoice(1,
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end

    test "returns {:error, map} when impl().pay_invoice/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _ -> {:error, %{}} end)

      assert Hexpm.Billing.pay_invoice(2,
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) == {:error, %{}}
    end

    test "does not create an Audit Log for pay_invoice whn imp().pay_invoice/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _ -> {:error, %{}} end)

      user = insert(:user)

      Hexpm.Billing.pay_invoice(3,
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [] = AuditLogs.all_by(user)
    end
  end
end
