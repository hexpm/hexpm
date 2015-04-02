defmodule HexWeb.Repo.Migrations.AddInstallsTable do
  use Ecto.Migration

  def up do
    "CREATE TABLE installs (
      id serial PRIMARY KEY,
      hex text,
      elixir text)"
  end

  def down do
    "DROP TABLE IF EXISTS installs"
  end
end
