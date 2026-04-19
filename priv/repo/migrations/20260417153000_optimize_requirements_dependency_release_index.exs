defmodule Hexpm.Repo.Migrations.OptimizeRequirementsDependencyReleaseIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    drop_if_exists(index(:requirements, [:dependency_id], concurrently: true))
    create_if_not_exists(index(:requirements, [:dependency_id, :release_id], concurrently: true))
  end

  def down() do
    drop_if_exists(index(:requirements, [:dependency_id, :release_id], concurrently: true))
    create_if_not_exists(index(:requirements, [:dependency_id], concurrently: true))
  end
end
