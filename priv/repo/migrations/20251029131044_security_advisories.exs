defmodule Hexpm.RepoBase.Migrations.SecurityAdvisories do
  use Ecto.Migration

  def change do
    create table(:security_advisories, primary_key: false) do
      add :id, :string, null: false, primary_key: true
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :summary, :string, null: false
      add :affected, {:array, :string}, null: false
      add :published_at, :utc_datetime, null: false
      add :modified_at, :utc_datetime, null: false
      add :details, :map, null: false
    end

    execute(
      """
      CREATE MATERIALIZED VIEW security_advisory_affected_releases AS
        SELECT DISTINCT
          security_advisories.id AS advisory_id,
          releases.id AS release_id
        FROM security_advisories
        CROSS JOIN LATERAL
          jsonb_array_elements(security_advisories.details->'affected')
          AS affected_entry
        CROSS JOIN LATERAL
          jsonb_array_elements_text(affected_entry->'versions')
          AS affected_version
        JOIN
          releases
          ON releases.package_id = security_advisories.package_id AND
            releases.version = affected_version
        WHERE affected_entry->'package'->>'ecosystem' = 'Hex'
      """,
      """
      DROP MATERIALIZED VIEW security_advisory_affected_releases
      """
    )

    create unique_index(:security_advisory_affected_releases, [:advisory_id, :release_id])
    create index(:security_advisory_affected_releases, [:advisory_id])
    create index(:security_advisory_affected_releases, [:release_id])
  end
end
