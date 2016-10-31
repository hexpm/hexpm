defmodule HexWeb.Repo.Migrations.ModifyEmailsUniqueConstraint do
  use Ecto.Migration

  def up do
    execute ~s{ALTER TABLE emails DROP CONSTRAINT emails_email_key}
    execute ~s{CREATE UNIQUE INDEX emails_email_key ON emails (email) WHERE verified = 'true'}
    execute ~s{CREATE UNIQUE INDEX emails_email_user_key ON emails (email, user_id)}
  end

  def down do
    execute ~s{DROP INDEX emails_email_key}
    execute ~s{DROP INDEX emails_email_user_key}
    execute ~s{ALTER TABLE emails ADD CONSTRAINT emails_email_key UNIQUE (email)}
  end
end
