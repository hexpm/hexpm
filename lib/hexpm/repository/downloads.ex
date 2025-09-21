defmodule Hexpm.Repository.Downloads do
  use Hexpm.Context

  def package(package) do
    PackageDownload.package(package)
    |> Repo.all()
    |> Map.new()
  end

  def packages_all_views(packages) do
    PackageDownload.packages_and_all_download_views(packages)
    |> Repo.all()
    |> Enum.reduce(%{}, fn {id, view, dls}, acc ->
      Map.update(acc, id, %{view => dls}, &Map.put(&1, view, dls))
    end)
  end

  def top_packages(repository, view, count) do
    top = Repo.all(PackageDownload.top(repository, view, count))

    packages =
      top
      |> Enum.map(fn {package, _downloads} -> package end)
      |> Packages.attach_latest_releases()

    Enum.zip_with(packages, top, fn package, {_package, downloads} ->
      {package, downloads}
    end)
  end

  def total() do
    PackageDownload.total()
    |> Repo.all()
    |> Map.new()
  end

  def for_period(package_or_release, group_by, opts \\ []) do
    base =
      case package_or_release do
        %Package{id: package_id} -> Download.by_period(package_id, group_by || :all)
        %Release{id: release_id} -> ReleaseDownload.by_period(release_id, group_by || :all)
      end

    query =
      opts
      |> Keyword.take([:downloads_after, :downloads_before])
      |> Enum.reduce(base, fn
        {:downloads_after, %Date{} = date}, query -> Download.since_date(query, date)
        {:downloads_after, nil}, query -> query
        {:downloads_before, %Date{} = date}, query -> Download.before_date(query, date)
        {:downloads_before, nil}, query -> query
      end)

    Repo.all(query)
  end

  def last_day() do
    Download.last_day()
    |> Repo.one()
  end
end
