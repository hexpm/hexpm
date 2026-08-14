defmodule Hexpm.Repo.Migrations.BackfillReleaseSemverSortKey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @batch_size 10_000

  def up do
    execute(fn ->
      backfill(repo())
      require_semver_fields(repo())
    end)
  end

  def down do
    execute(fn -> allow_null_semver_fields(repo()) end)
  end

  defp backfill(repo) do
    %{num_rows: rows} =
      query!(repo, """
      WITH batch AS (
        SELECT id
        FROM releases
        WHERE semver_sort_key IS NULL
        ORDER BY id
        LIMIT #{@batch_size}
      )
      UPDATE releases AS release
      SET semver_sort_key = ''::bytea
      FROM batch
      WHERE release.id = batch.id
      """)

    if rows == @batch_size, do: backfill(repo)
  end

  defp require_semver_fields(repo) do
    transaction(repo, fn ->
      query!(repo, "SET LOCAL lock_timeout TO '5s'")

      query!(repo, """
      ALTER TABLE releases
      ADD CONSTRAINT releases_semver_fields_present
      CHECK (semver_sort_key IS NOT NULL AND semver_stable IS NOT NULL) NOT VALID
      """)

      query!(repo, "ALTER TABLE releases VALIDATE CONSTRAINT releases_semver_fields_present")
      query!(repo, "ALTER TABLE releases ALTER COLUMN semver_sort_key SET NOT NULL")
      query!(repo, "ALTER TABLE releases ALTER COLUMN semver_stable SET NOT NULL")
      query!(repo, "ALTER TABLE releases DROP CONSTRAINT releases_semver_fields_present")
    end)
  end

  defp allow_null_semver_fields(repo) do
    transaction(repo, fn ->
      query!(repo, "SET LOCAL lock_timeout TO '5s'")

      query!(repo, """
      ALTER TABLE releases
      ALTER COLUMN semver_sort_key DROP NOT NULL,
      ALTER COLUMN semver_stable DROP NOT NULL
      """)
    end)
  end

  defp transaction(repo, fun) do
    {:ok, _result} = repo.transaction(fun, timeout: :infinity)
  end

  defp query!(repo, statement) do
    repo.query!(statement, [], timeout: :infinity)
  end
end
