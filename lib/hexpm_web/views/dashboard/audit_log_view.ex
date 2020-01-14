defmodule HexpmWeb.Dashboard.AuditLogView do
  use HexpmWeb, :view

  alias HexpmWeb.DashboardView

  @doc """
  Translate an audit_log to user readable descriptions
  """
  def humanize_audit_log_info(log = %{action: "docs.publish"}) do
    "Publish documentation for #{log.params["package"]["name"]} (#{
      log.params["release"]["version"]
    })"
  end

  def humanize_audit_log_info(log = %{action: "docs.revert"}) do
    "Revert documentation for #{log.params["package"]["name"]} (#{
      log.params["release"]["version"]
    })"
  end

  def humanize_audit_log_info(log = %{action: "key.generate"}) do
    "Generate key #{log.params["name"]}"
  end

  def humanize_audit_log_info(log = %{action: "key.remove"}) do
    "Remove key #{log.params["name"]}"
  end

  def humanize_audit_log_info(log = %{action: "owner.add"}) do
    "Add #{log.params["user"]["username"]} as a new owner of package #{
      log.params["package"]["name"]
    }"
  end

  def humanize_audit_log_info(log = %{action: "owner.transfer"}) do
    "Transfer package #{log.params["package"]["name"]} to #{log.params["user"]["username"]}"
  end

  def humanize_audit_log_info(log = %{action: "owner.remove"}) do
    "Remove #{log.params["user"]["username"]} from owners of package #{
      log.params["package"]["name"]
    }"
  end

  def humanize_audit_log_info(log = %{action: "release.publish"}) do
    "Publish package #{log.params["package"]["name"]} version #{log.params["release"]["version"]}"
  end

  def humanize_audit_log_info(log = %{action: "release.revert"}) do
    "Revert package #{log.params["package"]["name"]} version #{log.params["release"]["version"]}"
  end

  def humanize_audit_log_info(log = %{action: "release.retire"}) do
    "Retire package #{log.params["package"]["name"]} version #{log.params["release"]["version"]}"
  end

  def humanize_audit_log_info(log = %{action: "release.unretire"}) do
    "Unretire package #{log.params["package"]["name"]} version #{log.params["release"]["version"]}"
  end

  def humanize_audit_log_info(log = %{action: "email.add"}) do
    "Add email #{log.params["email"]}"
  end

  def humanize_audit_log_info(log = %{action: "email.remove"}) do
    "Remove email #{log.params["email"]}"
  end

  def humanize_audit_log_info(log = %{action: "email.primary"}) do
    "Set email #{log.params["email"]} as primary email"
  end

  def humanize_audit_log_info(log = %{action: "email.public"}) do
    "Set email #{log.params["email"]} as public email"
  end

  def humanize_audit_log_info(log = %{action: "email.gravatar"}) do
    "Set email #{log.params["email"]} as gravatar email"
  end

  def humanize_audit_log_info(_log = %{action: "user.create"}) do
    "Create user account"
  end

  def humanize_audit_log_info(_log = %{action: "user.update"}) do
    "Update user profile"
  end

  def humanize_audit_log_info(_log = %{action: "password.reset.init"}) do
    "Request to reset password"
  end

  def humanize_audit_log_info(_log = %{action: "password.reset.finish"}) do
    "Reset password successfully"
  end

  def humanize_audit_log_info(_log = %{action: "password.update"}) do
    "Update password"
  end
end
