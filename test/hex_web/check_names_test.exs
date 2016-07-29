defmodule HexWeb.CheckNamesTest do
  use HexWeb.ModelCase, async: true

  alias Mix.Tasks.Hexweb.CheckNames


  setup do
    yesterday =
      Ecto.DateTime.utc
      |> Ecto.DateTime.to_erl
      |> :calendar.datetime_to_gregorian_seconds
      |> Kernel.-(60 * 60 * 24 * 2)
      |> :calendar.gregorian_seconds_to_datetime
      |> Ecto.DateTime.from_erl

    # today's
    HexWeb.Repo.insert!(%HexWeb.Package{name: "hector"})
    HexWeb.Repo.insert!(%HexWeb.Package{name: "phoenics"})
    HexWeb.Repo.insert!(%HexWeb.Package{name: "poison"})
    # yesterday's
    HexWeb.Repo.insert!(%HexWeb.Package{name: "ecto", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Package{name: "phoenix", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Package{name: "potion", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Package{name: "asdf", inserted_at: yesterday})
    HexWeb.Repo.insert!(%HexWeb.Package{name: "conga", inserted_at: yesterday})

    {:ok, %{}}
  end

  test "check for typosquats", _ do
    assert length(CheckNames.current_packages) == 5
    assert length(CheckNames.new_packages) == 3

    threshold = 0.8
    assert length(CheckNames.find_candidates(threshold)) == 3
  end
end
