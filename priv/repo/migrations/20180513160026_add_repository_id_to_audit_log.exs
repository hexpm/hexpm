defmodule Hexpm.Repo.Migrations.AddRepositoryIdToAuditLog do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add(:repository_id, references(:repositories))
    end

    create(index(:audit_logs, [:actor_id]))
    create(index(:audit_logs, [:repository_id]))

    execute("ALTER TABLE audit_logs RENAME actor_id TO user_id")

    execute(
      "UPDATE audit_logs SET repository_id = (params->'repository'->'id' || params->'package'->'repository_id')::text::integer"
    )
  end
end
