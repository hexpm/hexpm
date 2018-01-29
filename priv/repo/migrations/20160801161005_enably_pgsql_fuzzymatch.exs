defmodule Hexpm.Repo.Migrations.EnablyPgsqlFuzzymatch do
  use Ecto.Migration

  def up() do
    execute("CREATE EXTENSION IF NOT EXISTS fuzzystrmatch")
  end

  def down() do
    raise "non reversible migration"
  end
end
