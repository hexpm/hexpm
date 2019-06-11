defmodule HexpmWeb.API.AuditLogViewTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.API.AuditLogView

  describe "render/2 show" do
    test "includes action" do
      audit_log = build(:audit_log, action: "test.action")

      assert %{action: "test.action"} = AuditLogView.render("show", %{audit_log: audit_log})
    end

    test "includes user_agent" do
      audit_log = build(:audit_log, user_agent: "Test User Agent")

      assert %{user_agent: "Test User Agent"} =
               AuditLogView.render("show", %{audit_log: audit_log})
    end

    test "includes params" do
      audit_log = build(:audit_log, params: %{test_key: "test_value"})

      assert %{params: %{test_key: "test_value"}} =
               AuditLogView.render("show", %{audit_log: audit_log})
    end
  end
end
