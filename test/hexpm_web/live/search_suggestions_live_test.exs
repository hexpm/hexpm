defmodule HexpmWeb.SearchSuggestionsLiveTest do
  use HexpmWeb.ConnCase

  import Phoenix.LiveViewTest

  # Share the sandbox connection with the LiveView process so DB calls inside
  # the LiveView (Packages.suggest/3) can see test data. Also provide a bare
  # conn so every test gets %{conn: conn} without repeating build_conn().
  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, {:shared, self()})
    {:ok, conn: build_conn()}
  end

  describe "home variant" do
    test "renders the search input", %{conn: conn} do
      {:ok, _view, html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      assert html =~ ~s(id="home-search-input")
      assert html =~ ~s(role="combobox")
      assert html =~ ~s(aria-controls="home-suggest-list")
    end

    test "shows suggestions as user types", %{conn: conn} do
      insert(:package, name: "phoenix_live_view")
      insert(:package, name: "phoenix_live_dashboard")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      html = view |> form("#search-suggestions-form", %{"search" => "phoenix"}) |> render_change()

      assert html =~ "phoenix_live_view"
      assert html =~ "phoenix_live_dashboard"
      assert html =~ ~s(role="listbox")
    end

    test "does not show dropdown until at least 3 characters are typed", %{conn: conn} do
      insert(:package, name: "phoenix_html")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      html = view |> form("#search-suggestions-form", %{"search" => "ph"}) |> render_change()
      refute html =~ ~s(role="listbox")

      html = view |> form("#search-suggestions-form", %{"search" => "pho"}) |> render_change()
      assert html =~ ~s(role="listbox")
    end

    test "hides dropdown when input is cleared", %{conn: conn} do
      insert(:package, name: "phoenix_html")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      view |> form("#search-suggestions-form", %{"search" => "phoenix"}) |> render_change()
      html = view |> form("#search-suggestions-form", %{"search" => ""}) |> render_change()

      refute html =~ ~s(role="listbox")
    end

    test "ArrowDown moves the highlight through suggestions", %{conn: conn} do
      insert(:package, name: "plug")
      insert(:package, name: "plug_crypto")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      view |> form("#search-suggestions-form", %{"search" => "plug"}) |> render_change()

      # First ArrowDown selects the first item (aria-selected="true")
      html = view |> element("input[phx-keydown]") |> render_keydown(%{"key" => "ArrowDown"})
      assert html =~ ~s(aria-selected="true")
    end

    test "submitting without ArrowDown performs a text search", %{conn: conn} do
      insert(:package, name: "ecto")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      # Type "ecto" to get suggestions but do NOT press ArrowDown
      view |> form("#search-suggestions-form", %{"search" => "ecto"}) |> render_change()

      # Submit goes to text search because active is nil
      view |> element("form") |> render_submit(%{"search" => "ecto"})
      assert_redirect(view, "/packages?search=ecto&sort=recent_downloads")
    end

    test "ArrowDown then submit navigates to the selected package", %{conn: conn} do
      insert(:package, name: "ecto")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      view |> form("#search-suggestions-form", %{"search" => "ecto"}) |> render_change()
      view |> element("input[phx-keydown]") |> render_keydown(%{"key" => "ArrowDown"})
      view |> element("form") |> render_submit(%{"search" => "ecto"})

      assert_redirect(view, "/packages/ecto")
    end

    test "submitting with no matching packages performs a text search", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      view |> element("form") |> render_submit(%{"search" => "no_match_xyzzy_12345"})
      assert_redirect(view, "/packages?search=no_match_xyzzy_12345&sort=recent_downloads")
    end

    test "Escape closes the dropdown", %{conn: conn} do
      insert(:package, name: "jason")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      view |> form("#search-suggestions-form", %{"search" => "jason"}) |> render_change()
      assert render(view) =~ ~s(role="listbox")

      html = view |> element("input[phx-keydown]") |> render_keydown(%{"key" => "Escape"})
      refute html =~ ~s(role="listbox")
    end

    test "close event closes the dropdown", %{conn: conn} do
      insert(:package, name: "bandit")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      view |> form("#search-suggestions-form", %{"search" => "bandit"}) |> render_change()
      assert render(view) =~ ~s(role="listbox")

      html = render_click(view, "close")
      refute html =~ ~s(role="listbox")
    end

    test "form recovery loads suggestions when connection is restored", %{conn: conn} do
      insert(:package, name: "phoenix_html")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "home"})

      html =
        view
        |> form("#search-suggestions-form", %{"search" => "phoenix"})
        |> render_change()

      assert html =~ "phoenix_html"
      assert html =~ ~s(role="listbox")
    end
  end

  describe "home-mobile variant" do
    test "uses distinct element IDs from the home variant", %{conn: conn} do
      {:ok, _view, html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive,
          session: %{"variant" => "home-mobile"}
        )

      assert html =~ ~s(id="home-mobile-search-input")
      assert html =~ ~s(aria-controls="home-mobile-suggest-list")
      refute html =~ ~s(id="home-search-input")
    end
  end

  describe "nav variant" do
    test "renders with nav-specific input ID", %{conn: conn} do
      {:ok, _view, html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "nav"})

      assert html =~ ~s(id="nav-search-input")
      assert html =~ ~s(aria-controls="nav-suggest-list")
    end

    test "shows suggestions as user types", %{conn: conn} do
      insert(:package, name: "req")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "nav"})

      html = view |> form("#nav-search-form", %{"search" => "req"}) |> render_change()

      assert html =~ "req"
      assert html =~ ~s(role="listbox")
    end

    test "shows syntax help footer when no package suggestions match", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "nav"})

      html =
        view
        |> form("#nav-search-form", %{"search" => "no_match_xyzzy_12345"})
        |> render_change()

      assert html =~ "No suggestions found"
      assert html =~ "Wildcard"
      assert html =~ "name:phx*"
      refute html =~ "Metadata"
      refute html =~ "extra:license,MIT"
      assert html =~ "Syntax Help"
      assert html =~ ~s(phx-click=)
    end

    test "submitting without ArrowDown performs a text search", %{conn: conn} do
      insert(:package, name: "oban")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "nav"})

      view |> form("#nav-search-form", %{"search" => "oban"}) |> render_change()
      view |> element("form") |> render_submit(%{"search" => "oban"})

      assert_redirect(view, "/packages?search=oban&sort=recent_downloads")
    end

    test "ArrowDown then submit navigates to the selected package", %{conn: conn} do
      insert(:package, name: "oban")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "nav"})

      view |> form("#nav-search-form", %{"search" => "oban"}) |> render_change()
      view |> element("input[phx-keydown]") |> render_keydown(%{"key" => "ArrowDown"})
      view |> element("form") |> render_submit(%{"search" => "oban"})

      assert_redirect(view, "/packages/oban")
    end

    test "form recovery loads suggestions when connection is restored", %{conn: conn} do
      insert(:package, name: "phoenix_html")

      {:ok, view, _html} =
        live_isolated(conn, HexpmWeb.SearchSuggestionsLive, session: %{"variant" => "nav"})

      html =
        view
        |> form("#nav-search-form", %{"search" => "phoenix"})
        |> render_change()

      assert html =~ "phoenix_html"
      assert html =~ ~s(role="listbox")
    end
  end
end
