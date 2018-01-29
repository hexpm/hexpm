defmodule Hexpm.Repo.Migrations.AddMetaToReleases do
  use Ecto.Migration

  def up() do
    alter table(:releases) do
      add(:meta, :jsonb)
    end

    execute("""
    UPDATE releases
      SET meta = json_build_object('app', app)::jsonb,
          has_docs = CASE WHEN has_docs IS NULL THEN false ELSE has_docs END
    """)

    alter table(:releases) do
      remove(:app)
    end
  end

  def drop() do
    alter table(:releases) do
      add(:app, :text)
    end

    execute("""
    UPDATE releases
      SET app = meta->'app'
    """)

    alter table(:releases) do
      remove(:meta)
    end
  end
end
