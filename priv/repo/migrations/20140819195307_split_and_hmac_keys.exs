defmodule Hexpm.Repo.Migrations.SplitAndHmacKeys do
  use Ecto.Migration

  def up() do
    secret = Application.get_env(:hexpm, :secret)

    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    execute("""
      ALTER TABLE keys
        ADD COLUMN secret_first text UNIQUE,
        ADD COLUMN secret_second text
    """)

    execute("""
      UPDATE keys
        SET secret_first  = encode(substring(hmac(secret, '#{secret}', 'sha256') for 16), 'hex'),
            secret_second = encode(substring(hmac(secret, '#{secret}', 'sha256') from 17), 'hex')
    """)

    execute("""
      ALTER TABLE keys
        DROP COLUMN secret
    """)
  end

  def down() do
    raise "Non reversible migration"
  end
end
