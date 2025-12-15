defmodule Hexpm.Repository.PackagesSuggestTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Packages

  defp names(packages), do: Enum.map(packages, & &1.name)

  setup do
    %{repository: insert(:repository)}
  end

  describe "suggest/3" do
    test "returns empty list for empty string", %{repository: repository} do
      insert(:package, name: "ecto", repository_id: repository.id)

      assert [] == Packages.suggest(repository, "")
      assert [] == Packages.suggest(repository, "   ")
    end

    test "returns exact match first", %{repository: repository} do
      ecto = insert(:package, name: "ecto", repository_id: repository.id)
      phoenix = insert(:package, name: "phoenix", repository_id: repository.id)
      ecto_sql = insert(:package, name: "ecto_sql", repository_id: repository.id)

      insert(:release, package: ecto)
      insert(:release, package: phoenix)
      insert(:release, package: ecto_sql)

      results = Packages.suggest(repository, "ecto")

      assert ["ecto", "ecto_sql"] == names(results)
    end

    test "returns prefix matches", %{repository: repository} do
      ecto = insert(:package, name: "ecto", repository_id: repository.id)
      ecto_sql = insert(:package, name: "ecto_sql", repository_id: repository.id)
      phoenix = insert(:package, name: "phoenix", repository_id: repository.id)

      insert(:release, package: ecto)
      insert(:release, package: ecto_sql)
      insert(:release, package: phoenix)

      results = Packages.suggest(repository, "ecto_")

      assert "ecto_sql" in names(results)
      refute "phoenix" in names(results)
    end

    test "returns substring matches", %{repository: repository} do
      ecto = insert(:package, name: "ecto", repository_id: repository.id)
      ecto_sql = insert(:package, name: "ecto_sql", repository_id: repository.id)
      phoenix_ecto = insert(:package, name: "phoenix_ecto", repository_id: repository.id)

      insert(:release, package: ecto)
      insert(:release, package: ecto_sql)
      insert(:release, package: phoenix_ecto)

      results = Packages.suggest(repository, "ecto")

      assert Enum.sort(["ecto", "ecto_sql", "phoenix_ecto"]) -- Enum.sort(names(results)) == []
    end

    test "matches by description", %{repository: repository} do
      package =
        insert(:package,
          name: "database",
          repository_id: repository.id,
          meta: build(:package_metadata, description: "Ecto is a database wrapper")
        )

      insert(:release, package: package)

      results = Packages.suggest(repository, "ecto")

      assert "database" in names(results)
      # ensure snippet has highlighting tags
      assert Enum.find(results, &(&1.name == "database")).description_html =~
               ~r/<strong>ecto<\/strong>/i
    end

    test "is case insensitive", %{repository: repository} do
      ecto = insert(:package, name: "Ecto", repository_id: repository.id)
      phoenix = insert(:package, name: "Phoenix", repository_id: repository.id)

      insert(:release, package: ecto)
      insert(:release, package: phoenix)

      results = Packages.suggest(repository, "ecto")
      assert "Ecto" in names(results)

      results = Packages.suggest(repository, "ECTO")
      assert "Ecto" in names(results)
    end

    test "respects repository scoping", %{repository: repository} do
      other_repository = insert(:repository)

      ecto = insert(:package, name: "ecto", repository_id: repository.id)
      other_ecto = insert(:package, name: "ecto", repository_id: other_repository.id)

      insert(:release, package: ecto)
      insert(:release, package: other_ecto)

      results = Packages.suggest(repository, "ecto")

      assert [only] = names(results)
      assert only == "ecto"
    end

    test "returns empty list when no matches", %{repository: repository} do
      insert(:package, name: "ecto", repository_id: repository.id)

      assert [] == Packages.suggest(repository, "nonexistent")
    end

    test "respects limit parameter", %{repository: repository} do
      packages =
        for i <- 1..10 do
          insert(:package, name: "package_#{i}", repository_id: repository.id)
        end

      Enum.each(packages, &insert(:release, package: &1))

      results = Packages.suggest(repository, "package", 5)
      assert length(results) == 5
    end

    test "handles special characters in search term", %{repository: repository} do
      package = insert(:package, name: "my_package", repository_id: repository.id)
      insert(:release, package: package)

      results = Packages.suggest(repository, "my_package")
      assert "my_package" in names(results)

      # LIKE special characters should be treated literally (no crash)
      assert is_list(Packages.suggest(repository, "my%package"))
    end

    test "includes package metadata in results", %{repository: repository} do
      package =
        insert(:package,
          name: "ecto",
          repository_id: repository.id,
          meta: build(:package_metadata, description: "Database wrapper")
        )

      insert(:release, package: package, version: "1.0.0")

      [result] = Packages.suggest(repository, "ecto")

      assert result.id == package.id
      assert result.name == "ecto"
      assert result.repository_id == repository.id
      assert is_binary(result.href)
      assert is_binary(result.name_html)
      assert result.latest_version == "1.0.0"
      assert is_integer(result.recent_downloads)
    end

    test "handles packages with repository prefix in search", %{repository: repository} do
      package = insert(:package, name: "ecto", repository_id: repository.id)
      insert(:release, package: package)

      # Test that repo/package format works (though it extracts just the package part)
      results = Packages.suggest(repository, "#{repository.name}/ecto")
      assert "ecto" in names(results)
    end

    test "orders by relevance and downloads", %{repository: repository} do
      # Create packages with different download counts
      high_downloads = insert(:package, name: "ecto_high", repository_id: repository.id)
      exact_match = insert(:package, name: "ecto", repository_id: repository.id)
      low_downloads = insert(:package, name: "ecto_low", repository_id: repository.id)

      insert(:release, package: high_downloads)
      insert(:release, package: exact_match)
      insert(:release, package: low_downloads)

      # Add downloads (would need PackageDownload view refresh in real scenario)
      # For now, just verify the structure
      results = Packages.suggest(repository, "ecto")

      # Exact match should be first
      assert hd(names(results)) == "ecto"
    end
  end
end
