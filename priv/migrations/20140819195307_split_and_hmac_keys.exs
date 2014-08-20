defmodule HexWeb.Repo.Migrations.SplitAndHmacKeys do
  use Ecto.Migration

  def up do
    secret = Application.get_env(:hex_web, :secret)

    [ "CREATE EXTENSION IF NOT EXISTS pgcrypto",
      "ALTER TABLE keys
        ADD COLUMN secret_first text UNIQUE,
        ADD COLUMN secret_second text",
      "UPDATE keys
        SET secret_first  = encode(substring(hmac(secret, '#{secret}', 'sha256') for 16), 'hex'),
            secret_second = encode(substring(hmac(secret, '#{secret}', 'sha256') from 17), 'hex')",
      "ALTER TABLE keys
        DROP COLUMN secret" ]
  end

  def down do
    raise "Non reversible migration"
  end
end
