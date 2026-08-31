defmodule Hexpm.RepoBase.Migrations.AddSidToOrganizationSso do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_sessions) do
      add :sid, :text
    end

    alter table(:organization_sso_transactions) do
      add :sid, :text
    end
  end
end
