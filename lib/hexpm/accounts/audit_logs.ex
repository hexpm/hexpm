defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  def all_by(%Hexpm.Repository.Package{} = package) do
    from(l in AuditLog,
      where: fragment("? @> ?", l.params, ^%{package: %{id: package.id}})
    )
    |> Repo.all()
  end

  def all_by(%Hexpm.Accounts.Organization{} = organization) do
    from(l in AuditLog, where: l.organization_id == ^organization.id)
    |> Repo.all()
  end

  def all_by(%Hexpm.Accounts.User{} = user) do
    from(l in AuditLog, where: l.user_id == ^user.id)
    |> Repo.all()
  end
end
