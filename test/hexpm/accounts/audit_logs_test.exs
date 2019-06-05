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
end
