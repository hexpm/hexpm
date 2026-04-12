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

  describe "build_tool checkbox" do
    setup do
      repository = Hexpm.Repository.Repositories.get("hexpm")
      mix_pkg = insert(:package, name: "mix_only", repository_id: repository.id)
      insert(:release, package: mix_pkg, meta: build(:release_metadata, build_tools: ["mix"]))

      rebar_pkg = insert(:package, name: "rebar_only", repository_id: repository.id)

      insert(:release,
        package: rebar_pkg,
        meta: build(:release_metadata, build_tools: ["rebar3"])
      )

      :ok
    end

    test "ticking a build_tool patches URL and narrows results", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/packages")
      html = render(view)
      assert html =~ "mix_only"
      assert html =~ "rebar_only"

      view
      |> form("#filter-form", %{"build_tool" => %{"mix" => "true"}})
      |> render_change()

      assert_patch(view, ~p"/packages?sort=recent_downloads&search=build_tool%3Amix")
      html = render(view)
      assert html =~ "mix_only"
      refute html =~ "rebar_only"
    end

    test "unticking a checked build_tool clears the filter from the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/packages?search=build_tool%3Amix")
      html = render(view)
      assert html =~ "mix_only"
      refute html =~ "rebar_only"

      # Simulate unticking: send the filter_change event with no build_tool key,
      # which is what a browser sends when all checkboxes are unchecked.
      # We bypass form/2 because LiveViewTest validates checkbox values against
      # the rendered DOM. render_change/3 dispatches directly to handle_event.
      render_change(view, "filter_change", %{})

      assert_patch(view, ~p"/packages?sort=recent_downloads")

      html = render(view)
      assert html =~ "mix_only"
      assert html =~ "rebar_only"
    end
  end

  describe "depends filter" do
    test "typing in depends narrows to packages that depend on the named package", %{conn: conn} do
      repository = Hexpm.Repository.Repositories.get("hexpm")
      ecto = insert(:package, name: "ecto_dep_src", repository_id: repository.id)
      insert(:package, name: "postgrex_dep_src", repository_id: repository.id)

      consumer = insert(:package, name: "ecto_consumer", repository_id: repository.id)
      release = insert(:release, package: consumer)
      insert(:requirement, release: release, dependency: ecto, requirement: "~> 1.0")

      Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant)

      {:ok, view, _} = live(conn, ~p"/packages")

      view
      |> form("#filter-form", %{"depends" => "ecto_dep_src"})
      |> render_change()

      html = render(view)
      assert html =~ "ecto_consumer"
      refute html =~ "postgrex_dep_src"
    end
  end
end
