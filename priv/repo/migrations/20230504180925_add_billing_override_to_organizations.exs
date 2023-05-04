defmodule Hexpm.RepoBase.Migrations.AddBillingOverrideToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add(:billing_override, :boolean)
    end
  end
end
