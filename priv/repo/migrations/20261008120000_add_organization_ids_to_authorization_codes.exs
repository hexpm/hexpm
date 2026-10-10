defmodule Hexpm.RepoBase.Migrations.AddOrganizationIdsToAuthorizationCodes do
  use Ecto.Migration

  def up do
    # The ALTER takes ACCESS EXCLUSIVE on a table every OAuth consent writes.
    # Give up rather than queue behind a long-running read and hold every
    # writer behind us.
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:authorization_codes) do
      add :organization_ids, {:array, :integer}, null: false, default: []
    end
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:authorization_codes) do
      remove :organization_ids
    end
  end
end
