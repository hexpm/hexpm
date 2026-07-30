defmodule Hexpm.Repo.Migrations.RenameEmailOutboxGroupKey do
  use Ecto.Migration

  def change do
    rename table(:email_outbox_entries), :ordering_key, to: :group_key

    execute(
      "ALTER INDEX email_outbox_entries_ordering_key_id_index RENAME TO email_outbox_entries_group_key_id_index",
      "ALTER INDEX email_outbox_entries_group_key_id_index RENAME TO email_outbox_entries_ordering_key_id_index"
    )
  end
end
