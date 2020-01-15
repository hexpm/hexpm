defmodule HexpmWeb.Dashboard.AuditLogViewTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Dashboard.AuditLogView

  describe "humanize_audit_log_info/1" do
    test "doc.publish" do
      log =
        build(:audit_log,
          action: "docs.publish",
          params: %{"package" => %{"name" => "Awesome"}, "release" => %{"version" => "0.2.4"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Publish documentation for Awesome (0.2.4)"
    end

    test "docs.revert" do
      log =
        build(:audit_log,
          action: "docs.revert",
          params: %{"package" => %{"name" => "Awesome"}, "release" => %{"version" => "0.2.4"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Revert documentation for Awesome (0.2.4)"
    end

    test "key.generate" do
      log = build(:audit_log, action: "key.generate", params: %{"name" => "Secret"})

      assert AuditLogView.humanize_audit_log_info(log) == "Generate key Secret"
    end

    test "key.remove" do
      log = build(:audit_log, action: "key.remove", params: %{"name" => "Secret"})

      assert AuditLogView.humanize_audit_log_info(log) == "Remove key Secret"
    end

    test "owner.add" do
      log =
        build(:audit_log,
          action: "owner.add",
          params: %{"package" => %{"name" => "Awesome"}, "user" => %{"username" => "John"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Add John as a new owner of package Awesome"
    end

    test "owner.transfer" do
      log =
        build(:audit_log,
          action: "owner.transfer",
          params: %{"package" => %{"name" => "Awesome"}, "user" => %{"username" => "John"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) == "Transfer package Awesome to John"
    end

    test "owner.remove" do
      log =
        build(:audit_log,
          action: "owner.remove",
          params: %{"package" => %{"name" => "Awesome"}, "user" => %{"username" => "John"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Remove John from owners of package Awesome"
    end

    test "release.publish" do
      log =
        build(:audit_log,
          action: "release.publish",
          params: %{"package" => %{"name" => "Awesome"}, "release" => %{"version" => "1.0.0"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) == "Publish package Awesome (1.0.0)"
    end

    test "release.revert" do
      log =
        build(:audit_log,
          action: "release.revert",
          params: %{"package" => %{"name" => "Awesome"}, "release" => %{"version" => "1.0.0"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) == "Revert package Awesome (1.0.0)"
    end

    test "release.retire" do
      log =
        build(:audit_log,
          action: "release.retire",
          params: %{"package" => %{"name" => "Awesome"}, "release" => %{"version" => "1.0.0"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) == "Retire package Awesome (1.0.0)"
    end

    test "release.unretire" do
      log =
        build(:audit_log,
          action: "release.unretire",
          params: %{"package" => %{"name" => "Awesome"}, "release" => %{"version" => "1.0.0"}}
        )

      assert AuditLogView.humanize_audit_log_info(log) == "Unretire package Awesome (1.0.0)"
    end

    test "email.add" do
      log = build(:audit_log, action: "email.add", params: %{"email" => "test@example.com"})

      assert AuditLogView.humanize_audit_log_info(log) == "Add email test@example.com"
    end

    test "email.remove" do
      log = build(:audit_log, action: "email.remove", params: %{"email" => "test@example.com"})

      assert AuditLogView.humanize_audit_log_info(log) == "Remove email test@example.com"
    end

    test "email.primary" do
      log = build(:audit_log, action: "email.primary", params: %{"email" => "test@example.com"})

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Set email test@example.com as primary email"
    end

    test "email.public" do
      log = build(:audit_log, action: "email.public", params: %{"email" => "test@example.com"})

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Set email test@example.com as public email"
    end

    test "email.gravatar" do
      log = build(:audit_log, action: "email.gravatar", params: %{"email" => "test@example.com"})

      assert AuditLogView.humanize_audit_log_info(log) ==
               "Set email test@example.com as gravatar email"
    end

    test "user.create" do
      log = build(:audit_log, action: "user.create")

      assert AuditLogView.humanize_audit_log_info(log) == "Create user account"
    end

    test "user.update" do
      log = build(:audit_log, action: "user.update")

      assert AuditLogView.humanize_audit_log_info(log) == "Update user profile"
    end

    test "password.reset.init" do
      log = build(:audit_log, action: "password.reset.init")

      assert AuditLogView.humanize_audit_log_info(log) == "Request to reset password"
    end

    test "password.reset.finish" do
      log = build(:audit_log, action: "password.reset.finish")

      assert AuditLogView.humanize_audit_log_info(log) == "Reset password successfully"
    end

    test "password.update" do
      log = build(:audit_log, action: "password.update")

      assert AuditLogView.humanize_audit_log_info(log) == "Update password"
    end
  end
end
