defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  def all_by(user) do
    from(l in AuditLog, where: l.user_id == ^user.id)
    |> Repo.all()
  end
end
