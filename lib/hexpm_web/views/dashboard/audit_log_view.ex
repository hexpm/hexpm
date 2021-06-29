defmodule HexpmWeb.Dashboard.AuditLogView do
  use HexpmWeb, :view

  alias HexpmWeb.DashboardView

  @doc """
  Translate an audit_log to user readable descriptions
  """
  def humanize_audit_log_info(%AuditLog{action: "docs.publish", params: params}) do
    "Publish documentation for #{params["package"]["name"]} (#{params["release"]["version"]})"
  end

  def humanize_audit_log_info(%AuditLog{action: "docs.revert", params: params}) do
    "Revert documentation for #{params["package"]["name"]} (#{params["release"]["version"]})"
  end

  def humanize_audit_log_info(%AuditLog{action: "key.generate", params: params}) do
    "Generate key #{params["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "key.remove", params: params}) do
    "Remove key #{params["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "owner.add", params: params}) do
    "Add #{params["user"]["username"]} as a new owner of package #{params["package"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "owner.transfer", params: params}) do
    "Transfer package #{params["package"]["name"]} to #{params["user"]["username"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "owner.remove", params: params}) do
    "Remove #{params["user"]["username"]} from owners of package #{params["package"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "release.publish", params: params}) do
    "Publish package #{params["package"]["name"]} (#{params["release"]["version"]})"
  end

  def humanize_audit_log_info(%AuditLog{action: "release.revert", params: params}) do
    "Revert package #{params["package"]["name"]} (#{params["release"]["version"]})"
  end

  def humanize_audit_log_info(%AuditLog{action: "release.retire", params: params}) do
    "Retire package #{params["package"]["name"]} (#{params["release"]["version"]})"
  end

  def humanize_audit_log_info(%AuditLog{action: "release.unretire", params: params}) do
    "Unretire package #{params["package"]["name"]} (#{params["release"]["version"]})"
  end

  def humanize_audit_log_info(%AuditLog{action: "email.add", params: params}) do
    "Add email #{params["email"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "email.remove", params: params}) do
    "Remove email #{params["email"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "email.primary", params: params}) do
    "Set email #{params["email"]} as primary email"
  end

  def humanize_audit_log_info(%AuditLog{
        action: "email.public",
        params: %{"old_email" => old_email, "new_email" => nil}
      }) do
    "Set email #{old_email["email"]} as private email"
  end

  def humanize_audit_log_info(%AuditLog{action: "email.public", params: params}) do
    "Set email #{params["email"]} as public email"
  end

  def humanize_audit_log_info(%AuditLog{action: "email.gravatar", params: params}) do
    "Set email #{params["email"]} as gravatar email"
  end

  def humanize_audit_log_info(%AuditLog{action: "user.create"}) do
    "Create user account"
  end

  def humanize_audit_log_info(%AuditLog{action: "user.update"}) do
    "Update user profile"
  end

  def humanize_audit_log_info(%AuditLog{action: "security.update"}) do
    "Update TFA settings"
  end

  def humanize_audit_log_info(%AuditLog{action: "security.rotate_recovery_codes"}) do
    "Rotate TFA recovery codes"
  end

  def humanize_audit_log_info(%AuditLog{action: "organization.create", params: params}) do
    "Create organization #{params["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "organization.member.add", params: params}) do
    "Add user #{params["user"]["username"]} to organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "organization.member.remove", params: params}) do
    "Remove user #{params["user"]["username"]} from organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "organization.member.role", params: params}) do
    "Change user #{params["user"]["username"]}'s role to #{params["role"]} " <>
      "in organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "password.reset.init"}) do
    "Request to reset password"
  end

  def humanize_audit_log_info(%AuditLog{action: "password.reset.finish"}) do
    "Reset password successfully"
  end

  def humanize_audit_log_info(%AuditLog{action: "password.update"}) do
    "Update password"
  end

  def humanize_audit_log_info(%AuditLog{action: "billing.checkout", params: params}) do
    "Update payment method for organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "billing.cancel", params: params}) do
    "Cancel billing on organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "billing.create", params: params}) do
    "Add billing information to organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "billing.update", params: params}) do
    "Update billing information for organization #{params["organization"]["name"]}"
  end

  def humanize_audit_log_info(%AuditLog{action: "billing.change_plan", params: params}) do
    "Change billing plan on organization #{params["organization"]["name"]} to " <>
      "#{plan_id(params["plan_id"])}"
  end

  def humanize_audit_log_info(%AuditLog{action: "billing.pay_invoice", params: params}) do
    "Manually pay invoice for organization #{params["organization"]["name"]}"
  end

  defp plan_id("organization-monthly"), do: "monthly"
  defp plan_id("organization-annually"), do: "annually"
end
