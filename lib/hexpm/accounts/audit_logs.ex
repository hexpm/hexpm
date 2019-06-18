defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  @audit_logs_per_page 10

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> Repo.all()
  end

  def all_by(schema, page) do
    AuditLog.all_by(schema)
    |> Hexpm.Utils.paginate(page, @audit_logs_per_page)
    |> Repo.all()
  end
end
