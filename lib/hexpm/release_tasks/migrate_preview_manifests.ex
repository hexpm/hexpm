defmodule Hexpm.ReleaseTasks.MigratePreviewManifests do
  import Ecto.Query

  require Logger

  alias Hexpm.Preview.Bucket
  alias Hexpm.Repository.{Package, Release, Repository}

  def run(opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)
    batch_size = Keyword.get(opts, :batch_size, 1_000)

    query =
      from release in Release,
        join: package in Package,
        on: package.id == release.package_id,
        join: repository in Repository,
        on: repository.id == package.repository_id,
        where: repository.name == "hexpm",
        order_by: release.id,
        select: {release.id, package.name, release.version}

    counts = migrate_batches(query, 0, batch_size, max_concurrency, %{})

    Logger.info("[task] Preview manifest migration: #{inspect(counts)}")
    counts
  end

  defp migrate_batches(query, last_id, batch_size, max_concurrency, counts) do
    batch =
      query
      |> where([release], release.id > ^last_id)
      |> limit(^batch_size)
      |> Hexpm.RepoBase.all()

    case batch do
      [] ->
        counts

      batch ->
        counts = migrate_batch(batch, max_concurrency, counts)
        {last_id, _package, _version} = List.last(batch)
        Logger.info("[task] Preview manifest migration progress: #{inspect(counts)}")
        migrate_batches(query, last_id, batch_size, max_concurrency, counts)
    end
  end

  defp migrate_batch(batch, max_concurrency, counts) do
    batch
    |> Task.async_stream(
      fn {_id, package, version} -> Bucket.migrate_manifest(package, to_string(version)) end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: 60_000
    )
    |> Enum.reduce(counts, fn
      {:ok, result}, counts -> Map.update(counts, result, 1, &(&1 + 1))
      {:exit, reason}, _counts -> exit(reason)
    end)
  end
end
