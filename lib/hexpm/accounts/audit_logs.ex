defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> Repo.all()
  end
end
