defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  @default_per_page 100

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> Repo.all()
  end

  def all_by(schema, page, per_page \\ @default_per_page) do
    AuditLog.all_by(schema)
    |> Hexpm.Utils.paginate(page, per_page)
    |> Repo.all()
  end
end
