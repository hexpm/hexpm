defmodule Hexpm.PackageSearches.PackageSearchTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.Repository.PackageSearches.PackageSearch

  describe "changeset/2" do
    test "with correct params, creates a package search" do
      params = %{"term" => "some_package_name"}
      assert %{valid?: true, changes: changes} = PackageSearch.changeset(%PackageSearch{}, params)
    end

    test "with increment request on existing package_search" do
      package_search = %PackageSearch{term: "common_package_name", frequency: 1, id: 1}
      params = %{"term" => "common_package_name"}
      assert %{valid?: true} = PackageSearch.changeset(package_search, params)
    end

    test "with incorrect params" do
      assert %{valid?: false, errors: errors} =
               PackageSearch.changeset(%PackageSearch{}, %{foo: 420})

      assert errors == [{:term, {"can't be blank", [validation: :required]}}]
    end
  end
end
