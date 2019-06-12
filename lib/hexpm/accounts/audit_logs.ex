defmodule Hexpm.Accounts.AuditLogs do
  use HexpmWeb, :context

  alias Hexpm.Accounts.AuditLog

  def all_by(%Hexpm.Repository.Package{} = package) do
    AuditLog.all_by(package)
    |> Repo.all()
  end

  def all_by(%Hexpm.Accounts.Organization{} = organization) do
    AuditLog.all_by(organization)
    |> Repo.all()
  end

  def all_by(%Hexpm.Accounts.User{} = user) do
    AuditLog.all_by(user)
    |> Repo.all()
  end
end
