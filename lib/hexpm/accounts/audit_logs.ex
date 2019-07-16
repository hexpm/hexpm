defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  @default_per_page 100

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> Repo.all()
  end

  def all_by(schema, page) do
    AuditLog.all_by(schema)
    |> Hexpm.Utils.paginate(page, @default_per_page)
    |> Repo.all()
  end
end
