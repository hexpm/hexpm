defmodule Hexpm.Repo.Migrations.CreateStagedReleases do
  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:organizations) do
      add :require_publish_approval, :boolean, null: false, default: false
    end

    alter table(:releases) do
      add :approved_by_id, references(:users, on_delete: :nilify_all)
    end

    create table(:staged_releases) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :version, :text, null: false
      add :kind, :text, null: false
      add :meta, :map, null: false, default: %{}
      add :replace, :boolean, null: false, default: false
      add :publication, :map
      add :inner_checksum, :binary
      add :outer_checksum, :binary
      add :storage_key, :text
      add :docs_checksum, :binary
      add :docs_storage_key, :text
      add :credential_type, :text, null: false
      add :credential_name, :text, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :organization_id, references(:organizations, on_delete: :nilify_all)
      add :key_id, references(:keys, on_delete: :nilify_all)
      add :workload_identity_id, references(:workload_identities, on_delete: :nilify_all)
      add :oidc_claims, :map
      add :expires_at, :utc_datetime_usec, null: false
      add :audit_data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:staged_releases, [:repository_id, :name, :version, :kind])
    create index(:staged_releases, [:expires_at])

    create constraint(:staged_releases, :staged_releases_kind,
             check: "kind IN ('release', 'docs')"
           )

    create constraint(:staged_releases, :staged_releases_credential_type,
             check: "credential_type IN ('key', 'workload_identity')"
           )
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    drop table(:staged_releases)

    alter table(:releases) do
      remove :approved_by_id
    end

    alter table(:organizations) do
      remove :require_publish_approval
    end
  end
end
