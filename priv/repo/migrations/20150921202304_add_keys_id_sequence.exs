defmodule HexWeb.Repo.Migrations.AddKeysIdSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE keys_id_seq START 1000"
    execute "ALTER TABLE keys ALTER COLUMN id SET DEFAULT nextval('keys_id_seq')"
    execute "UPDATE keys SET id = nextval('keys_id_seq') WHERE id IS NULL"
    execute "ALTER TABLE keys ALTER COLUMN id SET NOT NULL"
    execute "ALTER TABLE keys ADD PRIMARY KEY (id)"
  end

  def down do
    raise "Non reversible migration"
  end
end
