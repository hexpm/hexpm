defmodule Hexpm.Repository.PackagesSuggestTest do
  use Hexpm.DataCase

  alias Hexpm.Repository.Packages

  defp names(packages), do: Enum.map(packages, & &1.name)

  setup do
    %{repository: insert(:repository)}
  end

  describe "suggest/3" do
    test "returns empty list for fewer than 3 characters", %{repository: repository} do
      insert(:package, name: "ecto", repository_id: repository.id)

      assert [] == Packages.suggest(repository, "")
      assert [] == Packages.suggest(repository, "   ")
      assert [] == Packages.suggest(repository, "ec")
      assert [] == Packages.suggest(repository, "e")
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
      {:safe, description_string} = Enum.find(results, &(&1.name == "database")).description_html
      assert description_string =~ ~r/<strong>ecto<\/strong>/i
    end

    test "matches regardless of search term case", %{repository: repository} do
      ecto = insert(:package, name: "ecto", repository_id: repository.id)
      phoenix = insert(:package, name: "phoenix", repository_id: repository.id)

      insert(:release, package: ecto)
      insert(:release, package: phoenix)

      assert "ecto" in names(Packages.suggest(repository, "ecto"))
      assert "ecto" in names(Packages.suggest(repository, "ECTO"))
      assert "ecto" in names(Packages.suggest(repository, "Ecto"))
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
      assert {:safe, name_html} = result.name_html
      assert name_html =~ "ecto"
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
      # Names are chosen so alphabetical order is the reverse of expected download order:
      # "ecto_zzz" > "ecto_aaa" by downloads, but "ecto_aaa" < "ecto_zzz" alphabetically.
      # This proves downloads drive the ranking, not the fallback name sort.
      recent_day = Date.utc_today() |> Date.add(-7)
      high_downloads = insert(:package, name: "ecto_zzz", repository_id: repository.id)
      exact_match = insert(:package, name: "ecto", repository_id: repository.id)
      low_downloads = insert(:package, name: "ecto_aaa", repository_id: repository.id)

      insert(:release,
        package: high_downloads,
        daily_downloads: [
          build(:download, package_id: high_downloads.id, downloads: 1_000_000, day: recent_day)
        ]
      )

      insert(:release,
        package: exact_match,
        daily_downloads: [
          build(:download, package_id: exact_match.id, downloads: 500_000, day: recent_day)
        ]
      )

      insert(:release,
        package: low_downloads,
        daily_downloads: [
          build(:download, package_id: low_downloads.id, downloads: 500, day: recent_day)
        ]
      )

      :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload, concurrently: false)

      results = Packages.suggest(repository, "ecto")

      # Exact name match ("ecto") ranks first despite fewer downloads than "ecto_zzz"
      assert hd(names(results)) == "ecto"
      # Within the prefix-match tier, higher downloads rank first (not alphabetical)
      assert names(results) == ["ecto", "ecto_zzz", "ecto_aaa"]
    end

    test "name_html wraps matched portion in a mark element", %{repository: repository} do
      insert(:package, name: "ecto", repository_id: repository.id)

      [result] = Packages.suggest(repository, "ecto")

      assert {:safe, name_html} = result.name_html
      assert name_html == "<mark>ecto</mark>"
    end

    test "name_html highlights the matched portion", %{repository: repository} do
      insert(:package, name: "ecto_sql", repository_id: repository.id)

      [result] = Packages.suggest(repository, "ecto")

      assert {:safe, name_html} = result.name_html
      assert name_html == "<mark>ecto</mark>_sql"
    end

    test "description_html does not pass raw HTML tags from descriptions", %{
      repository: repository
    } do
      # A description containing an HTML tag should never appear unescaped in the output.
      # ts_headline wraps matched terms in <strong> but surrounding text (including any
      # HTML in the description) must be escaped.
      insert(:package,
        name: "mypackage",
        repository_id: repository.id,
        meta: build(:package_metadata, description: "mypackage <em>emphasis</em> here")
      )

      [result] = Packages.suggest(repository, "mypackage")

      assert {:safe, desc_html} = result.description_html
      # The <em> from the description must not appear as raw HTML
      refute desc_html =~ ~r/<em[^>]*>/
      # Only <strong> tags (from ts_headline markup) are permitted
      assert Regex.scan(~r/<\w/, desc_html) |> Enum.all?(fn [tag] -> tag == "<s" end)
    end
  end
end
