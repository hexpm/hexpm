defmodule Hexpm.Repo.Migrations.CreateCdnWritesSequence do
  use Ecto.Migration

  def up do
    execute("CREATE SEQUENCE cdn_writes")
  end

  def down do
    execute("DROP SEQUENCE cdn_writes")
  end
end
