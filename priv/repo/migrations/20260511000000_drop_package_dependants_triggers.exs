defmodule Hexpm.Repo.Migrations.DropPackageDependantsTriggers do
  use Ecto.Migration

  def up() do
    execute("DROP TRIGGER IF EXISTS package_dependants_after_requirement_insert ON requirements")
    execute("DROP TRIGGER IF EXISTS package_dependants_after_requirement_delete ON requirements")
    execute("DROP TRIGGER IF EXISTS package_dependants_before_release_delete ON releases")
    execute("DROP TRIGGER IF EXISTS package_dependants_after_release_delete ON releases")

    execute("DROP FUNCTION IF EXISTS package_dependants_insert()")
    execute("DROP FUNCTION IF EXISTS package_dependants_delete()")
    execute("DROP FUNCTION IF EXISTS package_dependants_cache_deleted_release()")
    execute("DROP FUNCTION IF EXISTS package_dependants_cleanup_deleted_releases()")

    drop_if_exists table(:package_dependants_deleted_releases)
  end

  def down() do
    raise Ecto.MigrationError,
      message: "this migration is irreversible; the trigger-based maintenance has been retired"
  end
end
