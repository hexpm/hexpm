defmodule HexWeb.Repo.Migrations.ChangeInstallsElixirReqToArray do
  use Ecto.Migration

  def up do
    [ "ALTER TABLE installs
        ADD elixirs text[]",
      "UPDATE installs
        SET elixirs = ARRAY[elixir]",
      "ALTER TABLE installs
        DROP elixir" ]
  end

  def down do
    [ "ALTER TABLE installs
        ADD elixir text",
      "UPDATE installs
        SET elixir = elixirs[1]",
      "ALTER TABLE installs
        DROP elixirs" ]
  end
end
