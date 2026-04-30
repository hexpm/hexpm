defmodule Hexpm.RepoBase.Migrations.SecurityAdvisories do
  use Ecto.Migration

  def change do
    create table(:security_advisories, primary_key: false) do
      add :id, :string, null: false, primary_key: true
      add :summary, :string, null: false
      add :aliases, {:array, :string}, null: false, default: []
      add :published_at, :utc_datetime, null: false
      add :modified_at, :utc_datetime, null: false
      add :withdrawn_at, :utc_datetime
      add :cvss_vector, :string
      add :cvss_score, :float
      add :cvss_rating, :string
    end

    create table(:security_advisory_references) do
      add :advisory_id,
          references(:security_advisories, type: :string, on_delete: :delete_all),
          null: false

      add :type, :string, null: false
      add :url, :string, null: false
    end

    create index(:security_advisory_references, [:advisory_id])

    create table(:security_advisory_affected_packages, primary_key: false) do
      add :advisory_id,
          references(:security_advisories, type: :string, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :package_id,
          references(:packages, on_delete: :delete_all),
          null: false,
          primary_key: true
    end

    create index(:security_advisory_affected_packages, [:package_id])

    create table(:security_advisory_affected_versions) do
      add :advisory_id,
          references(:security_advisories, type: :string, on_delete: :delete_all),
          null: false

      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :requirement, :string, null: false
    end

    create index(:security_advisory_affected_versions, [:advisory_id])
    create index(:security_advisory_affected_versions, [:package_id])

    create table(:security_advisory_affected_releases, primary_key: false) do
      add :advisory_id,
          references(:security_advisories, type: :string, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :release_id,
          references(:releases, on_delete: :delete_all),
          null: false,
          primary_key: true
    end

    create index(:security_advisory_affected_releases, [:release_id])
  end
end
