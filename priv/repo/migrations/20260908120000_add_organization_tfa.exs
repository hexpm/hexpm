defmodule Hexpm.RepoBase.Migrations.AddOrganizationTFA do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :tfa_required_at, :utc_datetime_usec
      add :tfa_policy_revision, :integer, null: false, default: 0
    end
  end
end
