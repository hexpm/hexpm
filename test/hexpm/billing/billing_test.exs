defmodule Hexpm.BillingTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{AuditLog, AuditLogs}

  describe "checkout/3" do
    test "returns {:ok, whatever} when impl().checkout/2 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :checkout, fn "name", %{payment_source: :anything} ->
        {:ok, :whatever}
      end)

      assert Hexpm.Billing.checkout("name", %{payment_source: :anything},
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) == {:ok, :whatever}
    end

    test "creates an Audit Log when impl().checkout/2 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :checkout, fn _, _ -> {:ok, :whatever} end)

      user = insert(:user)

      Hexpm.Billing.checkout("name", %{},
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [%AuditLog{action: "billing.checkout"}] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().checkout/2 fails" do
      Mox.stub(Hexpm.Billing.Mock, :checkout, fn "name", %{payment_source: :anything} ->
        {:error, :reason}
      end)

      assert Hexpm.Billing.checkout("name", %{payment_source: :anything},
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) == {:error, :reason}
    end

    test "does not create an Audit Log when impl().checkout/2 fails" do
      Mox.stub(Hexpm.Billing.Mock, :checkout, fn _, _ -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.checkout("name", %{payment_source: :anything},
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [] == AuditLogs.all_by(user)
    end
  end

  describe "cancel/2" do
    test "returns whatever impl().cancel/1 returns" do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn "organization token" -> :whatever end)

      assert Hexpm.Billing.cancel("organization token",
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) == :whatever
    end

    test "creates an Audit Log for billing.cancel" do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn "organization token" -> :whatever end)

      user = insert(:user)

      Hexpm.Billing.cancel("organization token",
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [%AuditLog{action: "billing.cancel"}] = AuditLogs.all_by(user)
    end
  end

  describe "create/2" do
    test "returns {:ok, whatever} when impl().create/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:ok, :whatever} end)

      assert Hexpm.Billing.create(%{},
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) ==
               {:ok, :whatever}
    end

    test "creates an Audit Log for billing.create when impl().create/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:ok, %{}} end)

      user = insert(:user)

      Hexpm.Billing.create(%{},
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [%AuditLog{action: "billing.create"}] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().create/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:error, :reason} end)

      assert Hexpm.Billing.create(%{},
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) ==
               {:error, :reason}
    end

    test "does not create an Audit Log when impl().create/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.create(%{},
        audit: %{audit_data: audit_data(user), organization: nil}
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
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) ==
               {:ok, :whatever}
    end

    test "creates an Audit Log for billing.update when impl().update/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _params -> {:ok, %{}} end)

      user = insert(:user)

      Hexpm.Billing.update("organization token", %{},
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [%AuditLog{action: "billing.update"}] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().update/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _params -> {:error, :reason} end)

      assert Hexpm.Billing.update("organization token", %{},
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) ==
               {:error, :reason}
    end

    test "does not create an Audit Log when impl().update/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _params -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.update("organization token", %{},
        audit: %{audit_data: audit_data(user), organization: nil}
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
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) == :ok
    end

    test "creates an Audit Log for billing.change_plan" do
      Mox.stub(Hexpm.Billing.Mock, :change_plan, fn _, _ -> :ok end)

      user = insert(:user)

      Hexpm.Billing.change_plan("organization token", %{"plan_id" => "new_plan"},
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [%AuditLog{action: "billing.change_plan"}] = AuditLogs.all_by(user)
    end
  end

  describe "pay_invoice/2" do
    test "returns :ok when impl().pay_invoice/1 returns :ok" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn 238 -> :ok end)

      assert Hexpm.Billing.pay_invoice(238,
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) == :ok
    end

    test "creates an Audit Log for pay_invoice when imp().pay_invoice/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _ -> :ok end)

      user = insert(:user)

      Hexpm.Billing.pay_invoice(1,
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [%AuditLog{action: "billing.pay_invoice"}] = AuditLogs.all_by(user)
    end

    test "returns {:error, map} when impl().pay_invoice/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _ -> {:error, %{}} end)

      assert Hexpm.Billing.pay_invoice(2,
               audit: %{audit_data: audit_data(insert(:user)), organization: nil}
             ) == {:error, %{}}
    end

    test "does not create an Audit Log for pay_invoice when imp().pay_invoice/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _ -> {:error, %{}} end)

      user = insert(:user)

      Hexpm.Billing.pay_invoice(3,
        audit: %{audit_data: audit_data(user), organization: nil}
      )

      assert [] = AuditLogs.all_by(user)
    end
  end
end
