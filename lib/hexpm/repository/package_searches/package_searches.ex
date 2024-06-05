defmodule Hexpm.Repository.PackageSearches do
  use Hexpm.Context
  alias Hexpm.Repository.PackageSearches.PackageSearch

  def add_or_increment(params) do
    case get(params["term"]) do
      nil -> add(%PackageSearch{}, params)
      %PackageSearch{} = package_search -> increment(package_search)
    end
  end

  def get(term) do
    Repo.get_by(PackageSearch, term: term)
  end

  def all do
    query =
      from(
        ps in PackageSearch,
        order_by: [desc: ps.frequency],
        select: [:term, :frequency],
        where: ps.frequency > 1,
        limit: 100
      )

    Repo.all(query)
  end

  defp add(package_search, params) do
    package_search
    |> PackageSearch.changeset(params)
    |> Repo.insert()
  end

  defp increment(package_search) do
    package_search
    |> PackageSearch.changeset(%{})
    |> put_change(:frequency, package_search.frequency + 1)
    |> Repo.update()
  end
end
