defmodule Hexpm.Repository.PackageDependants do
  import Ecto.Query

  alias Hexpm.Repo
  alias Hexpm.Repository.{Package, PackageDependant, Release, Requirement}

  @lock_class_id 0xD3D3
  @backfill_batch_size 1000

  def recompute_for_package(repo, package) do
    take_lock(repo, package.id)

    releases = repo.all(from(r in Release, where: r.package_id == ^package.id))

    latest = Release.latest_version(releases, only_stable: true, unstable_fallback: true)

    sync_rows(repo, package, latest)

    {:ok, latest}
  end

  def backfill() do
    backfill(0)
  end

  defp backfill(after_id) do
    packages =
      from(p in Package,
        where: p.id > ^after_id,
        order_by: p.id,
        limit: @backfill_batch_size
      )
      |> Repo.all()

    case packages do
      [] ->
        :ok

      packages ->
        Enum.each(packages, fn package ->
          {:ok, _} = Repo.transaction(fn -> recompute_for_package(Repo, package) end)
        end)

        backfill(List.last(packages).id)
    end
  end

  defp sync_rows(repo, package, nil) do
    repo.delete_all(from(pd in PackageDependant, where: pd.package_id == ^package.id))
  end

  defp sync_rows(repo, package, latest) do
    dependency_ids =
      repo.all(
        from(req in Requirement, where: req.release_id == ^latest.id, select: req.dependency_id)
      )

    delete_stale_rows(repo, package, dependency_ids)
    insert_missing_rows(repo, package, dependency_ids)
  end

  defp delete_stale_rows(repo, package, []) do
    repo.delete_all(from(pd in PackageDependant, where: pd.package_id == ^package.id))
  end

  defp delete_stale_rows(repo, package, dependency_ids) do
    repo.delete_all(
      from(pd in PackageDependant,
        where: pd.package_id == ^package.id and pd.dependency_id not in ^dependency_ids
      )
    )
  end

  defp insert_missing_rows(_repo, _package, []), do: :ok

  defp insert_missing_rows(repo, package, dependency_ids) do
    entries =
      Enum.map(dependency_ids, fn dependency_id ->
        %{
          dependency_id: dependency_id,
          package_id: package.id,
          dependant_repository_id: package.repository_id
        }
      end)

    repo.insert_all(PackageDependant, entries, on_conflict: :nothing)
    :ok
  end

  defp take_lock(repo, package_id) do
    if Application.get_env(:hexpm, :skip_advisory_locks, false) do
      :ok
    else
      repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_class_id, package_id])
      :ok
    end
  end
end
