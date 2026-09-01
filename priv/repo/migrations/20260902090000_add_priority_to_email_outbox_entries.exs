defmodule Hexpm.Repo.Migrations.AddPriorityToEmailOutboxEntries do
  use Ecto.Migration

  def change do
    alter table(:email_outbox_entries) do
      add :priority, :integer, null: false, default: 0
    end
  end
end
