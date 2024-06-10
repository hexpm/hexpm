defmodule Hexpm.Repository.PackageSearches do
  use Hexpm.Context
  alias Hexpm.Repository.PackageSearches.PackageSearch

  def add_or_increment(params) do
    %PackageSearch{}
    |> PackageSearch.changeset(params)
    |> Repo.insert(on_conflict: [inc: [frequency: 1]], conflict_target: :term)
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
end
