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

  def by_period(%Release{id: release_id}, filter) do
    ReleaseDownload.by_period(release_id, filter || :all)
    |> Repo.all()
  end

  def last_day() do
    Download.last_day()
    |> Repo.one()
  end

  def since_date(%Package{id: package_id}, date) do
    package_id
    |> Download.by_period(:day)
    |> Download.since_date(date)
    |> Repo.all()
  end

  def since_date(%Release{id: release_id}, date) do
    release_id
    |> ReleaseDownload.by_period(:day)
    |> Download.since_date(date)
    |> Repo.all()
  end
end
