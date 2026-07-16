defmodule HexpmWeb.PackageVersionsControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user)

    repository1 = insert(:repository)

    package1 = insert(:package)
    package2 = insert(:package, repository_id: repository1.id)

    insert(
      :release,
      package: package1,
      version: "0.0.1",
      meta: build(:release_metadata, app: package1.name)
    )

    insert(
      :release,
      package: package1,
      version: "0.0.2",
      meta: build(:release_metadata, app: package1.name)
    )

    insert(
      :release,
      package: package1,
      version: "0.0.3-dev",
      meta: build(:release_metadata, app: package1.name)
    )

    insert(
      :release,
      package: package2,
      version: "1.0.0",
      meta: build(:release_metadata, app: package2.name)
    )

    insert(
      :release,
      package: package2,
      version: "0.1.0",
      meta: build(:release_metadata, app: package2.name)
    )

    insert(:organization_user, user: user1, organization: repository1.organization)

    %{
      package1: package1,
      package2: package2,
      repository1: repository1,
      user1: user1
    }
  end

  describe "GET /packages/:package_name/versions" do
    test "list all versions for public package", %{package1: package1} do
      conn = get(build_conn(), "/packages/#{package1.name}/versions")
      result = response(conn, 200)
      assert result =~ "0.0.1"
      assert result =~ "0.0.2"
      assert result =~ "0.0.3-dev"
      assert result =~ package1.name

      assert {:ok, document} = Floki.parse_document(result)

      for version <- ~w(0.0.1 0.0.2 0.0.3-dev) do
        assert [_ | _] =
                 Floki.find(
                   document,
                   ~s(a[href="/packages/#{package1.name}/#{version}/files"])
                 )
      end
    end

    test "list private package versions", %{
      user1: user1,
      package2: package2,
      repository1: repository1
    } do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{repository1.name}/#{package2.name}/versions")

      result = response(conn, 200)
      assert result =~ "0.1.0"
      assert result =~ "1.0.0"
      assert result =~ package2.name
    end

    test "paginates versions 100 per page and keeps previous-version diff links", %{
      package1: package1
    } do
      Enum.each(4..101, fn patch ->
        insert(
          :release,
          package: package1,
          version: "0.0.#{patch}",
          meta: build(:release_metadata, app: package1.name)
        )
      end)

      first_page =
        build_conn()
        |> get("/packages/#{package1.name}/versions")
        |> response(200)

      {:ok, first_document} = Floki.parse_document(first_page)
      first_page_versions = release_link_texts(first_document, package1.name)

      assert "0.0.101" in first_page_versions
      assert "0.0.2" in first_page_versions
      refute "0.0.1" in first_page_versions
      assert first_page =~ "/packages/#{package1.name}/versions?page=2"
      assert first_page =~ "/diff/#{package1.name}/0.0.1..0.0.2"

      second_page =
        build_conn()
        |> get("/packages/#{package1.name}/versions?page=2")
        |> response(200)

      {:ok, second_document} = Floki.parse_document(second_page)
      second_page_versions = release_link_texts(second_document, package1.name)

      assert "0.0.1" in second_page_versions
      refute "0.0.101" in second_page_versions
      assert current_page(second_document) == "2"
      assert normalized_text(second_document) =~ "101 total"
    end

    test "unauthenticated access to private package versions returns 404", %{
      package2: package2,
      repository1: repository1
    } do
      conn = get(build_conn(), "/packages/#{repository1.name}/#{package2.name}/versions")
      assert response(conn, 404)
    end

    test "user without org access cannot view private package versions", %{
      package2: package2,
      repository1: repository1
    } do
      other_user = insert(:user)

      conn =
        build_conn()
        |> test_login(other_user)
        |> get("/packages/#{repository1.name}/#{package2.name}/versions")

      assert response(conn, 404)
    end
  end

  defp release_link_texts(document, package_name) do
    document
    |> Floki.find("table tbody a")
    |> Enum.filter(fn link ->
      case Floki.attribute(link, "href") do
        [href] ->
          String.starts_with?(href, "/packages/#{package_name}/") &&
            href != "/packages/#{package_name}/versions"

        _ ->
          false
      end
    end)
    |> Enum.map(&Floki.text(&1, sep: " "))
    |> Enum.map(&String.trim/1)
  end

  defp current_page(document) do
    case Floki.find(document, ~s([aria-current="page"])) do
      [page | _rest] -> Floki.text(page, sep: " ") |> String.trim()
      [] -> nil
    end
  end

  defp normalized_text(document) do
    document
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
