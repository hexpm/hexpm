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

  describe "build_tool dropdown" do
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

    test "selecting a build_tool patches URL and narrows results", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/packages")
      html = render(view)
      assert html =~ "mix_only"
      assert html =~ "rebar_only"

      view
      |> form("#filter-form", %{"build_tool" => "mix"})
      |> render_change()

      assert_patch(view, ~p"/packages?sort=recent_downloads&search=build_tool%3Amix")
      html = render(view)
      assert html =~ "mix_only"
      refute html =~ "rebar_only"
    end

    test "selecting Any clears the filter from the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/packages?search=build_tool%3Amix")
      html = render(view)
      assert html =~ "mix_only"
      refute html =~ "rebar_only"

      view
      |> form("#filter-form", %{"build_tool" => ""})
      |> render_change()

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
      recompute_dependants(consumer)

      {:ok, view, _} = live(conn, ~p"/packages")

      view
      |> form("#filter-form", %{"depends" => "ecto_dep_src"})
      |> render_change()

      html = render(view)
      assert html =~ "ecto_consumer"
      refute html =~ "postgrex_dep_src"
    end
  end

  describe "updated_after filter" do
    test "narrows results by date", %{conn: conn} do
      repository = Hexpm.Repository.Repositories.get("hexpm")

      insert(:package,
        name: "old_pkg",
        repository_id: repository.id,
        updated_at: ~U[2020-01-01 00:00:00Z]
      )

      insert(:package,
        name: "new_pkg",
        repository_id: repository.id,
        updated_at: ~U[2025-06-01 00:00:00Z]
      )

      {:ok, view, _} = live(conn, ~p"/packages")
      html = render(view)
      assert html =~ "old_pkg"
      assert html =~ "new_pkg"

      view
      |> form("#filter-form", %{"updated_after" => "2024-01-01"})
      |> render_change()

      assert_patch(
        view,
        ~p"/packages?sort=recent_downloads&search=updated_after%3A2024-01-01T00%3A00%3A00Z"
      )

      html = render(view)
      assert html =~ "new_pkg"
      refute html =~ "old_pkg"
    end
  end

  describe "clear filters" do
    test "clear all button resets the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/packages?search=build_tool%3Amix")

      view |> element("#clear-filters") |> render_click()
      assert_patch(view, ~p"/packages?sort=recent_downloads")
    end
  end

  describe "multi-filter integration" do
    test "combined URL narrows results and pre-fills the sidebar", %{conn: conn} do
      repository = Hexpm.Repository.Repositories.get("hexpm")

      # Target: uses mix, depends on ecto, recently updated, has license=MIT
      ecto =
        insert(:package, name: "ecto_combo_dep", repository_id: repository.id)

      target =
        insert(:package,
          name: "combo_target",
          repository_id: repository.id,
          updated_at: ~U[2025-06-01 00:00:00Z],
          meta: build(:package_metadata, extra: %{"license" => "MIT"})
        )

      target_release =
        insert(:release, package: target, meta: build(:release_metadata, build_tools: ["mix"]))

      insert(:requirement, release: target_release, dependency: ecto, requirement: "~> 1.0")
      recompute_dependants(target)

      # Non-matching: uses rebar3 (wrong build_tool) — should NOT appear.
      other =
        insert(:package,
          name: "combo_other",
          repository_id: repository.id,
          updated_at: ~U[2025-06-01 00:00:00Z],
          meta: build(:package_metadata, extra: %{"license" => "MIT"})
        )

      other_release =
        insert(:release, package: other, meta: build(:release_metadata, build_tools: ["rebar3"]))

      insert(:requirement, release: other_release, dependency: ecto, requirement: "~> 1.0")
      recompute_dependants(other)

      query =
        "build_tool:mix depends:ecto_combo_dep updated_after:2024-01-01T00:00:00Z extra:license,MIT"

      url = ~p"/packages?search=#{query}"

      {:ok, _view, html} = live(conn, url)

      # Intersection is narrowed correctly.
      assert html =~ "combo_target"
      refute html =~ "combo_other"

      # Sidebar controls are pre-filled:
      # - build_tool dropdown has mix selected
      assert html =~ ~s(value="mix" selected)
      # - depends input is populated
      assert html =~ ~s(name="depends" value="ecto_combo_dep")
      # - updated_after date is populated with the date portion
      assert html =~ ~s(name="updated_after" value="2024-01-01")
    end
  end
end
