defmodule Hexpm.Repo.Migrations.RecordEmailOutboxDeliveries do
  use Ecto.Migration

  def up do
    alter table(:email_outbox_entries) do
      add :recipients, {:array, :text}
      add :subject, :text
      add :delivered_at, :utc_datetime_usec
      add :provider_message_id, :text
    end

    create index(:email_outbox_entries, [:delivered_at])

    flush()

    execute """
    UPDATE email_outbox_entries
    SET subject = email->>'subject',
        recipients = ARRAY(
          SELECT recipient->>'address'
          FROM jsonb_array_elements((email->'to') || (email->'cc') || (email->'bcc')) AS recipient
        )
    """
  end

  def down do
    drop index(:email_outbox_entries, [:delivered_at])

    alter table(:email_outbox_entries) do
      remove :recipients
      remove :subject
      remove :delivered_at
      remove :provider_message_id
    end
  end
end
