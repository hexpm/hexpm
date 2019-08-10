defmodule Hexpm.Accounts.AuditLogs do
  use Hexpm.Context

  alias Hexpm.Accounts.AuditLog

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> Repo.all()
  end

  def all_by(schema, page, per_page) do
    AuditLog.all_by(schema)
    |> Hexpm.Utils.paginate(page, per_page)
    |> Repo.all()
  end
end
