defmodule Hexpm.Repo.Migrations.AddTypeToEmailOutboxEntries do
  use Ecto.Migration

  def change do
    alter table(:email_outbox_entries) do
      add :type, :text
    end
  end
end
