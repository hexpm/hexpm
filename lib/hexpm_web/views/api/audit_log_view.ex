defmodule HexpmWeb.API.AuditLogView do
  use HexpmWeb, :view

  def render("show", %{audit_log: audit_log}) do
    Map.take(audit_log, [:action, :user_agent, :params])
  end
end
