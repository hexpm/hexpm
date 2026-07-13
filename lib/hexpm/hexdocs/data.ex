defmodule Hexpm.Hexdocs.Data do
  import Ecto.Query

  alias Hexpm.Repo
  alias Hexpm.Repository.{Package, Release, Repository, Sitemaps}

  def versions(repository, package) do
    from(r in Release,
      join: p in Package,
      on: p.id == r.package_id,
      join: repository in Repository,
      on: repository.id == p.repository_id,
      where: repository.name == ^repository and p.name == ^package and r.has_docs,
      order_by: [desc: r.version],
      select: {r.version, r.retirement}
    )
    |> Repo.all()
    |> Enum.map(fn {version, retirement} -> {parse_version(version), retirement} end)
    |> then(fn releases ->
      versions = releases |> Enum.map(&elem(&1, 0)) |> Enum.sort({:desc, Version})
      retired = for {version, retirement} <- releases, retirement, into: MapSet.new(), do: version
      {versions, retired}
    end)
  end

  defp parse_version(%Version{} = version), do: version
  defp parse_version(version), do: Version.parse!(version)

  def public_package_names do
    from(p in Package,
      join: repository in Repository,
      on: repository.id == p.repository_id,
      where: repository.name == "hexpm",
      order_by: p.name,
      select: p.name
    )
    |> Repo.all()
  end

  def docs_sitemap do
    Sitemaps.packages_with_docs()
    |> Sitemaps.render_docs()
  end
end
