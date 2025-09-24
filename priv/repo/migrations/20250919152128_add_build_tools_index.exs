defmodule Hexpm.RepoBase.Migrations.AddBuildToolsIndex do
  use Ecto.Migration

  def up do
    execute("CREATE INDEX releases_meta_build_tools_idx ON releases USING GIN ((meta->'build_tools'));")
  end

  def down do
    execute("DROP INDEX IF EXISTS releases_meta_build_tools_idx;")
  end
end
