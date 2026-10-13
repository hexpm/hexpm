defmodule Hexpm.RepoBase.Migrations.AddSearchDisabledAtToPackages do
  use Ecto.Migration

  def up do
    # The ALTER takes ACCESS EXCLUSIVE on a table every publish writes. Give
    # up rather than queue behind a long-running read and hold every writer
    # behind us.
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:packages) do
      add :search_disabled_at, :utc_datetime_usec
    end
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:packages) do
      remove :search_disabled_at
    end
  end
end
