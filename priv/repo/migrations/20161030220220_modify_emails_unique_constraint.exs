defmodule Hexpm.Repo.Migrations.ModifyEmailsUniqueConstraint do
  use Ecto.Migration

  def up() do
    execute("ALTER TABLE emails DROP CONSTRAINT emails_email_key")
    execute("CREATE UNIQUE INDEX emails_email_key ON emails (email) WHERE verified = 'true'")
    execute("CREATE UNIQUE INDEX emails_email_user_key ON emails (email, user_id)")
  end

  def down() do
    execute("DROP INDEX emails_email_key")
    execute("DROP INDEX emails_email_user_key")
    execute("ALTER TABLE emails ADD CONSTRAINT emails_email_key UNIQUE (email)")
  end
end
