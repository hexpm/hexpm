defmodule Hexpm.Repo.Migrations.MoveContributorsToMaintainers do
  use Ecto.Migration

  def up() do
    execute("""
      UPDATE packages
        SET meta = json_object_delete_keys(
                     json_object_set_key(meta::json, 'maintainers', meta->'contributors'),
                     'contributors')::jsonb
        WHERE (meta->'contributors') IS NOT NULL
    """)
  end

  def down() do
    execute("""
      UPDATE packages
        SET meta = json_object_delete_keys(
                     json_object_set_key(meta::json, 'contributors', meta->'maintainers'),
                     'maintainers')::jsonb
        WHERE (meta->'maintainers') IS NOT NULL
    """)
  end
end
