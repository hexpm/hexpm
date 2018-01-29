defmodule Hexpm.Repo.Migrations.AddPermissionsToKeys do
  use Ecto.Migration

  def up() do
    alter table(:keys) do
      add(
        :permissions,
        {:array, :jsonb},
        null: false,
        default: fragment("ARRAY[json_build_object('id', uuid_generate_v4(), 'domain', 'api')]")
      )
    end

    execute("ALTER TABLE keys ALTER permissions DROP DEFAULT")
  end

  def down() do
    alter table(:keys) do
      remove(:permissions)
    end
  end
end
