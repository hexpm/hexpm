defmodule Hexpm.Accounts.AuditLogsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.AuditLogs

  describe "all_by(user)" do
    test "returns audit_logs belong to this user" do
      this_user = insert(:user)
      audit_log = insert(:audit_log, user: this_user)

      assert [audit_log_fetched] = AuditLogs.all_by(this_user)
      assert audit_log_fetched.id == audit_log.id
    end

    test "does not return audit_logs that do not belong to this user" do
      this_user = insert(:user)
      other_user = insert(:user)
      _audit_log = insert(:audit_log, user: other_user)

      assert [] = AuditLogs.all_by(this_user)
    end
  end

  describe "all_by(organization)" do
    test "returns audit_logs belong to this organization" do
      this_org = insert(:organization)
      audit_log = insert(:audit_log, organization: this_org)

      assert [audit_log_fetched] = AuditLogs.all_by(this_org)
      assert audit_log_fetched.id == audit_log.id
    end

    test "does not return audit_logs that do not belong to this organization" do
      this_org = insert(:organization)
      other_org = insert(:organization)
      _audit_log = insert(:audit_log, organization: other_org)

      assert [] = AuditLogs.all_by(this_org)
    end
  end

  describe "all_by(package)" do
    test "returns audit_logs that have are created for this package" do
      this_package = insert(:package)
      audit_log = insert(:audit_log, params: %{package: %{id: this_package.id}})

      assert [audit_log_fetched] = AuditLogs.all_by(this_package)
      assert audit_log_fetched.id == audit_log.id
    end

    test "does not return audit_logs that are NOT created for this package" do
      this_package = insert(:package)
      other_package = insert(:package)
      _audit_log = insert(:audit_log, params: %{package: %{id: other_package.id}})

      assert [] = AuditLogs.all_by(this_package)
    end

    test "does not return audit_logs that do not have package in params" do
      this_package = insert(:package)
      _audit_log = insert(:audit_log, params: %{})

      assert [] = AuditLogs.all_by(this_package)
    end

    test "orders audit_logs by inserted_at timestamp" do
      this_package = insert(:package)

      insert(:audit_log,
        params: %{identifier: "new", package: %{id: this_package.id}},
        inserted_at: ~N{2019-08-10 10:00:00}
      )

      insert(:audit_log,
        params: %{identifier: "old", package: %{id: this_package.id}},
        inserted_at: ~N{2019-07-10 10:00:00}
      )

      assert [%{params: %{"identifier" => "new"}}, %{params: %{"identifier" => "old"}}] =
               AuditLogs.all_by(this_package)
    end
  end

  describe "all_by(user, page, per_page)" do
    test "returns 10 audit logs per page" do
      user = insert(:user)
      insert_list(11, :audit_log, user: user)

      results = AuditLogs.all_by(user, 1, 10)

      assert length(results) == 10
    end

    test "returns audit_logs in page 2 with 10 audit logs per page" do
      user = insert(:user)
      # NOTE: the order is desc: :inserted_at by default,
      # so we insert audit_log in second page first
      insert(:audit_log, action: "test.second.page", user: user)
      insert_list(10, :audit_log, action: "test.first.page", user: user)

      assert [%{action: "test.second.page"}] = AuditLogs.all_by(user, 2, 10)
    end
  end
end
