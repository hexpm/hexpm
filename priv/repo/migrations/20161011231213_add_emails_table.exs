defmodule HexWeb.Repo.Migrations.AddEmailsTable do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE emails (
      id serial PRIMARY KEY,
      email varchar(255) UNIQUE,
      verified boolean,
      "primary" boolean,
      public boolean,
      verification_key varchar(255),
      user_id integer REFERENCES users ON DELETE CASCADE
    )
    """

    execute ~s{CREATE UNIQUE INDEX ON emails (user_id, "primary")}
    execute ~s{CREATE UNIQUE INDEX ON emails (user_id, public)}

    execute """
    INSERT INTO emails (email, verified, "primary", public, verification_key, user_id)
      SELECT users.email, users.confirmed, TRUE, TRUE, users.confirmation_key, users.id
      FROM users
    """

    execute """
    ALTER TABLE users
      DROP COLUMN email,
      DROP COLUMN confirmed,
      DROP COLUMN confirmation_key
    """
  end

  def down do
    raise "non reversible migration"
  end
end
