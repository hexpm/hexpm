defmodule HexpmWeb.Dashboard.AuditLogView do
  use HexpmWeb, :view

  alias HexpmWeb.DashboardView

  @doc """
  Translate an audit_log to user readable descriptions
  """
  def humanize_audit_log_info(%{action: "docs.publish"} = log) do
    "Publish documentation for #{log.params["package"]["name"]} (#{
      log.params["release"]["version"]
    })"
  end

  def humanize_audit_log_info(%{action: "docs.revert"} = log) do
    "Revert documentation for #{log.params["package"]["name"]} (#{
      log.params["release"]["version"]
    })"
  end

  def humanize_audit_log_info(%{action: "key.generate"} = log) do
    "Generate key #{log.params["name"]}"
  end

  def humanize_audit_log_info(%{action: "key.remove"} = log) do
    "Remove key #{log.params["name"]}"
  end

  def humanize_audit_log_info(%{action: "owner.add"} = log) do
    "Add #{log.params["user"]["username"]} as a new owner of package #{
      log.params["package"]["name"]
    }"
  end

  def humanize_audit_log_info(%{action: "owner.transfer"} = log) do
    "Transfer package #{log.params["package"]["name"]} to #{log.params["user"]["username"]}"
  end

  def humanize_audit_log_info(%{action: "owner.remove"} = log) do
    "Remove #{log.params["user"]["username"]} from owners of package #{
      log.params["package"]["name"]
    }"
  end

  def humanize_audit_log_info(%{action: "release.publish"} = log) do
    "Publish package #{log.params["package"]["name"]} (#{log.params["release"]["version"]})"
  end

  def humanize_audit_log_info(%{action: "release.revert"} = log) do
    "Revert package #{log.params["package"]["name"]} (#{log.params["release"]["version"]})"
  end

  def humanize_audit_log_info(%{action: "release.retire"} = log) do
    "Retire package #{log.params["package"]["name"]} (#{log.params["release"]["version"]})"
  end

  def humanize_audit_log_info(%{action: "release.unretire"} = log) do
    "Unretire package #{log.params["package"]["name"]} (#{log.params["release"]["version"]})"
  end

  def humanize_audit_log_info(%{action: "email.add"} = log) do
    "Add email #{log.params["email"]}"
  end

  def humanize_audit_log_info(%{action: "email.remove"} = log) do
    "Remove email #{log.params["email"]}"
  end

  def humanize_audit_log_info(%{action: "email.primary"} = log) do
    "Set email #{log.params["email"]} as primary email"
  end

  def humanize_audit_log_info(%{action: "email.public"} = log) do
    "Set email #{log.params["email"]} as public email"
  end

  def humanize_audit_log_info(%{action: "email.gravatar"} = log) do
    "Set email #{log.params["email"]} as gravatar email"
  end

  def humanize_audit_log_info(%{action: "user.create"} = _log) do
    "Create user account"
  end

  def humanize_audit_log_info(%{action: "user.update"} = _log) do
    "Update user profile"
  end

  def humanize_audit_log_info(%{action: "organization.create"} = log) do
    "Create organization #{log.params["name"]}"
  end

  def humanize_audit_log_info(%{action: "organization.member.add"} = log) do
    "Add user #{log.params["user"]["username"]} to organization #{
      log.params["organization"]["name"]
    }"
  end

  def humanize_audit_log_info(%{action: "organization.member.remove"} = log) do
    "Remove user #{log.params["user"]["username"]} from organization #{
      log.params["organization"]["name"]
    }"
  end

  def humanize_audit_log_info(%{action: "organization.member.role"} = log) do
    "Change user #{log.params["user"]["username"]}'s role to #{log.params["role"]} in organization #{
      log.params["organization"]["name"]
    }"
  end

  def humanize_audit_log_info(%{action: "password.reset.init"} = _log) do
    "Request to reset password"
  end

  def humanize_audit_log_info(%{action: "password.reset.finish"} = _log) do
    "Reset password successfully"
  end

  def humanize_audit_log_info(%{action: "password.update"} = _log) do
    "Update password"
  end

  def humanize_audit_log_info(%{action: action} = _log) do
    action
  end
end
