defmodule HexpmWeb.PackageLive.IndexTest do
  use HexpmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup do
    repository = Hexpm.Repository.Repositories.get("hexpm")
    phoenix = insert(:package, name: "phoenix_test_pkg", repository_id: repository.id)
    ecto = insert(:package, name: "ecto_test_pkg", repository_id: repository.id)
    insert(:release, package: phoenix)
    insert(:release, package: ecto)
    %{phoenix: phoenix, ecto: ecto, conn: build_conn()}
  end

  test "renders package list via live/2", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/packages")
    assert html =~ "Packages"
    assert html =~ "phoenix_test_pkg"
    assert html =~ "ecto_test_pkg"
  end

  test "renders on dead HTTP GET (no LiveView connection)", %{conn: conn} do
    conn = get(conn, ~p"/packages")
    assert html_response(conn, 200) =~ "phoenix_test_pkg"
    assert html_response(conn, 200) =~ "ecto_test_pkg"
  end

  test "filters by search param", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/packages?search=phoenix_test_pkg")
    assert html =~ "phoenix_test_pkg"
    refute html =~ "ecto_test_pkg"
  end

  test "renders without crashing on malformed extra: query", %{conn: conn} do
    # SearchQuery.parse returns {:error, ...} for this input; LiveView must not crash.
    {:ok, _view, html} = live(conn, ~p"/packages?search=extra:no_comma")
    assert html =~ "Packages"
  end
end
