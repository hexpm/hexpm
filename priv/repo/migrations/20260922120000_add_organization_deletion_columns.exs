defmodule Hexpm.Repo.Migrations.AddOrganizationDeletionColumns do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :billing_inactive_since, :utc_datetime_usec
      add :deletion_scheduled_at, :utc_datetime_usec
      add :deletion_notices, {:array, :string}, null: false, default: []
    end

    execute """
    UPDATE organizations
    SET billing_inactive_since = now()
    WHERE id <> 1
      AND billing_active = false
      AND billing_override IS DISTINCT FROM true
      AND trial_end < now()
    """
  end

  def down do
    alter table(:organizations) do
      remove :billing_inactive_since
      remove :deletion_scheduled_at
      remove :deletion_notices
    end
  end
end
