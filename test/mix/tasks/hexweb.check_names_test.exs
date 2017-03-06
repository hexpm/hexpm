defmodule Mix.Tasks.Hexweb.CheckNamesTest do
  use HexWeb.ModelCase, async: true

  alias Mix.Tasks.Hexweb.CheckNames

  setup do
    {:ok, yesterday} = NaiveDateTime.new(HexWeb.Utils.utc_yesterday, ~T[00:00:00.000])

    # today's
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "hector"})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "phoenics"})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "poison"})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "poizon"})
    # yesterday's
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "ecto", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "phoenix", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "potion", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "asdf", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "conga", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "foo", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Repository.Package{name: "fooo", inserted_at: yesterday})

    :ok
  end

  test "check for typosquats", _ do
    assert length(CheckNames.find_candidates(2)) == 5
  end
end
