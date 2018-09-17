defmodule Hexpm.ReleaseTasks.CheckNamesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.ReleaseTasks.CheckNames

  setup do
    {:ok, yesterday} = NaiveDateTime.new(Hexpm.Utils.utc_yesterday(), ~T[00:00:00.000])

    # today's
    insert(:package, name: "hector")
    insert(:package, name: "phoenics")
    insert(:package, name: "poison")
    insert(:package, name: "poizon")
    # yesterday's
    insert(:package, name: "ecto", inserted_at: yesterday)
    insert(:package, name: "phoenix", inserted_at: yesterday)
    insert(:package, name: "potion", inserted_at: yesterday)
    insert(:package, name: "asdf", inserted_at: yesterday)
    insert(:package, name: "conga", inserted_at: yesterday)
    insert(:package, name: "foo", inserted_at: yesterday)
    insert(:package, name: "fooo", inserted_at: yesterday)

    :ok
  end

  test "check for typosquats", _ do
    assert length(CheckNames.find_candidates(2)) == 5
  end
end
