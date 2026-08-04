defmodule Hexpm.RepoBase.Migrations.CreateSecretScans do
  use Ecto.Migration

  def change do
    # One row per release that has been looked at, so a release with nothing in
    # it is distinguishable from one that was never scanned.
    create table(:secret_scans) do
      add :release_id, references(:releases, on_delete: :delete_all), null: false
      add :tarball_checksum, :binary, null: false
      add :finding_count, :integer, null: false, default: 0
      add :truncated, :boolean, null: false, default: false
      add :notified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:secret_scans, [:release_id])

    # Never the credential itself: only an HMAC of it and a masked preview. The
    # tarball_checksum ties a finding to the exact content it was found in,
    # because a release can be overwritten within its grace window and the same
    # release_id then points at a different tarball.
    create table(:secret_findings) do
      add :release_id, references(:releases, on_delete: :delete_all), null: false
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :tarball_checksum, :binary, null: false
      add :rule, :text, null: false
      add :file_path, :text, null: false
      add :line, :integer, null: false
      add :byte_offset, :integer, null: false
      add :fingerprint, :binary, null: false
      add :preview, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:secret_findings, [:release_id, :fingerprint])

    # Notification dedupes per package, not per release, so republishing the
    # same secret across ten versions is one email.
    create index(:secret_findings, [:package_id, :fingerprint])
  end
end
