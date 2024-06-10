defmodule Hexpm.PackageSearchesTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.Repository.PackageSearches
  alias Hexpm.Repository.PackageSearches.PackageSearch

  describe "add_or_increment/1" do
    test "with correct params, creates a new package search" do
      term = "new_package_name"
      params = %{"term" => term}
      {:ok, package_search} = PackageSearches.add_or_increment(params)
      assert package_search.term == term
      assert package_search.frequency == 1
    end

    test "with correct params, updates an existing package search" do
      term = "existing_package_name"
      package_search = %PackageSearch{term: term}
      Repo.insert(package_search)
      params = %{"term" => term}
      {:ok, _updated_package_search} = PackageSearches.add_or_increment(params)
      updated_package_search = Repo.get_by(PackageSearch, term: term)
      assert updated_package_search.frequency == 2
    end

    test "with incorrect params, errors instead of creating a new package_search" do
      params = %{"term" => ""}
      assert {:error, %{valid?: false}} = PackageSearches.add_or_increment(params)
    end
  end

  describe "get/1" do
    setup do
      Repo.insert(%PackageSearch{term: "popular_package"})
      :ok
    end

    test "given a package_search that exists, returns a record" do
      assert PackageSearches.get("popular_package")
    end

    test "given a package_search that does not exist, returns nil" do
      refute PackageSearches.get("zyxwv")
    end
  end

  describe "all/0" do
    setup do
      Repo.insert(%PackageSearch{term: "popular_package_a", frequency: 100})
      Repo.insert(%PackageSearch{term: "popular_package_b", frequency: 69})
      Repo.insert(%PackageSearch{term: "popular_package_c", frequency: 42})
      Repo.insert(%PackageSearch{term: "popular_package_d", frequency: 1})
      :ok
    end

    test "returns the packages in descending order of frequency" do
      package_searches =
        PackageSearches.all()
        |> Enum.map(fn package_search -> Map.take(package_search, [:term, :frequency]) end)

      assert package_searches == [
               %{frequency: 100, term: "popular_package_a"},
               %{frequency: 69, term: "popular_package_b"},
               %{frequency: 42, term: "popular_package_c"}
             ]
    end

    test "returns only the packages with frequency greater than 1" do
      package_searches = PackageSearches.all()
      assert Enum.all?(package_searches, fn package_search -> package_search.frequency > 1 end)
    end
  end
end
