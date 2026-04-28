defmodule HexpmWeb.Dashboard.Organization.Components.AuditLogsTab do
  @moduledoc """
  Recent Activities tab content for the organization dashboard.
  Reuses the shared audit_log_card component. Pagination is rendered by the
  parent template since it requires access to Phoenix view render helpers.
  """
  use Phoenix.Component

  import HexpmWeb.Dashboard.AuditLog.Components.AuditLogCard, only: [audit_log_card: 1]

  attr :audit_logs, :list, required: true

  def audit_logs_tab(assigns) do
    ~H"""
    <.audit_log_card audit_logs={@audit_logs} />
    """
  end
end
