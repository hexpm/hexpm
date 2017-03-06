defmodule Mix.Tasks.Hexpm.CheckNamesTest do
  use Hexpm.DataCase, async: true

  alias Mix.Tasks.Hexpm.CheckNames

  setup do
    {:ok, yesterday} = NaiveDateTime.new(Hexpm.Utils.utc_yesterday, ~T[00:00:00.000])

    # today's
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "hector"})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "phoenics"})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "poison"})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "poizon"})
    # yesterday's
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "ecto", inserted_at: yesterday})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "phoenix", inserted_at: yesterday})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "potion", inserted_at: yesterday})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "asdf", inserted_at: yesterday})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "conga", inserted_at: yesterday})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "foo", inserted_at: yesterday})
    Hexpm.Repo.insert!(%Hexpm.Repository.Package{name: "fooo", inserted_at: yesterday})

    :ok
  end

  test "check for typosquats", _ do
    assert length(CheckNames.find_candidates(2)) == 5
  end
end
