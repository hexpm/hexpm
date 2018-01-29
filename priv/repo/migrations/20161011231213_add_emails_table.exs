defmodule Hexpm.Repo.Migrations.AddEmailsTable do
  use Ecto.Migration

  def up() do
    execute("""
    CREATE TABLE emails (
      id serial PRIMARY KEY,
      email varchar(255) UNIQUE,
      verified boolean,
      "primary" boolean,
      public boolean,
      verification_key varchar(255),
      user_id integer REFERENCES users ON DELETE CASCADE,
      inserted_at timestamp,
      updated_at timestamp
    )
    """)

    # (Ab)uses the fact that unique indexes are not considered equal for NULL values
    execute(
      ~s{CREATE UNIQUE INDEX ON emails (user_id, (CASE WHEN "primary" THEN TRUE ELSE NULL END))}
    )

    execute(
      ~s{CREATE UNIQUE INDEX ON emails (user_id, (CASE WHEN public THEN TRUE ELSE NULL END))}
    )

    execute("""
    INSERT INTO emails (email, verified, "primary", public, verification_key, user_id, inserted_at, updated_at)
      SELECT users.email, users.confirmed, TRUE, TRUE, users.confirmation_key, users.id, users.inserted_at, users.updated_at
      FROM users
    """)

    execute("""
    ALTER TABLE users
      DROP COLUMN email,
      DROP COLUMN confirmed,
      DROP COLUMN confirmation_key
    """)
  end

  def down() do
    raise "non reversible migration"
  end
end
