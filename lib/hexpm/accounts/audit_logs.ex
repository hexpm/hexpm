defmodule Hexpm.Accounts.AuditLogs do
  use Hexpm.Context

  alias Hexpm.Accounts.AuditLog

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> AuditLog.newest_first()
    |> Repo.all()
  end

  def all_by(schema, page, per_page) do
    AuditLog.all_by(schema)
    |> AuditLog.newest_first()
    |> Hexpm.Utils.paginate(page, per_page)
    |> Repo.all()
  end

  @doc """
  Return the number of audit_logs belong to the schema (user/organization/package)
  """
  def count_by(schema) do
    AuditLog.count_by(schema)
    |> Repo.one()
  end
end
