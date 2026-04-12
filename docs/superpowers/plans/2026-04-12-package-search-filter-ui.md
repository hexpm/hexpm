# Package Search Filter UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hexpm's package search filter operators (`name:`, `description:`, `depends:`, `build_tool:`, `updated_after:`, `extra:`) discoverable and usable without typing, via a faceted filter sidebar on `/packages` and a cheatsheet modal reachable from the navbar search on every page.

**Architecture:** Convert `/packages` index to a Phoenix LiveView (`HexpmWeb.PackageLive.Index`) — hexpm's first user-facing LiveView. The URL is the source of truth: sidebar controls parse and re-serialize into the existing `search` query param so bookmarks stay compatible. A new pure `Hexpm.Repository.Package.SearchQuery` module owns parse/serialize and supports mixed free-text + filter strings (today's parser is all-or-nothing). `Package.all/6` is unchanged except `search_param("build_tool", ...)` gains multi-value OR semantics to power checkbox facets.

**Tech Stack:** Phoenix 1.7 + Phoenix LiveView, Ecto, PostgreSQL (jsonb/array ops), TailwindCSS, ExUnit, Phoenix.LiveViewTest.

**Spec:** `docs/superpowers/specs/2026-04-12-package-search-filter-ui-design.md`

---

## File Structure

**New files:**

- `lib/hexpm/repository/package/search_query.ex` — pure parse/serialize for search strings.
- `lib/hexpm_web/live/init_assigns.ex` — on_mount hook assigning `:current_user` from the session.
- `lib/hexpm_web/live/package_live/index.ex` — the LiveView (mount, handle_params, handle_event, render).
- `lib/hexpm_web/live/package_live/filter_sidebar.ex` — function component rendering the sidebar.
- `lib/hexpm_web/live/package_live/filter_cheatsheet.ex` — function component for the `?` modal contents.
- `test/hexpm/repository/package/search_query_test.exs` — SearchQuery unit tests.
- `test/hexpm_web/live/package_live/index_test.exs` — LiveView tests.
- `test/hexpm_web/live/package_live/filter_cheatsheet_test.exs` — modal render test.

**Modified files:**

- `lib/hexpm_web/web.ex` — add a `live_view/0` helper for `use HexpmWeb, :live_view`.
- `lib/hexpm_web/router.ex` — add a `live_session` with `live "/packages", PackageLive.Index, :index` replacing the existing `get "/packages", ...` line; keep the remaining controller routes.
- `lib/hexpm_web/controllers/package_controller.ex` — delete the `index/2` action and its private helpers that become orphaned (`sort/1` if only used by index, `fetch_packages/5`, `exact_match/2`). Keep `show`, `dependencies`, `dependents`, `versions`, `audit_logs` and their helpers untouched.
- `lib/hexpm_web/components/navbar.ex` — add a `?` icon button next to the search input that opens `#search-cheatsheet-modal`, and render `<.filter_cheatsheet />` once in the app layout.
- `lib/hexpm/repository/package.ex` — extend `search_param("build_tool", ...)` to accept a list of values (OR semantics) while preserving single-string behaviour.
- `test/hexpm/repository/package_test.exs` — extend existing build_tool tests with the multi-value OR case.
- `lib/hexpm_web/templates/layout/app.html.heex` (or wherever the navbar is rendered across all pages) — render the cheatsheet modal once so it's available site-wide.

**Deleted:** `lib/hexpm_web/templates/package/index.html.heex` is moved into the LiveView's `render/1` (or into a sibling `index.html.heex` co-located with the LiveView — see Task 6 for the chosen layout).

---

## Task 1: SearchQuery parse — failing tests

**Files:**
- Create: `lib/hexpm/repository/package/search_query.ex`
- Create: `test/hexpm/repository/package/search_query_test.exs`

- [ ] **Step 1: Create the empty module so the test file compiles**

```elixir
# lib/hexpm/repository/package/search_query.ex
defmodule Hexpm.Repository.Package.SearchQuery do
  @moduledoc false

  defstruct free_text: nil,
            depends: nil,
            build_tools: [],
            updated_after: nil,
            extra: [],
            name: nil,
            description: nil,
            unknown: []

  def parse(_string), do: raise("not implemented")
  def serialize(_query), do: raise("not implemented")
end
```

- [ ] **Step 2: Write the parse test**

```elixir
# test/hexpm/repository/package/search_query_test.exs
defmodule Hexpm.Repository.Package.SearchQueryTest do
  use ExUnit.Case, async: true

  alias Hexpm.Repository.Package.SearchQuery

  describe "parse/1" do
    test "nil and empty string return an empty query" do
      assert {:ok, %SearchQuery{}} = SearchQuery.parse(nil)
      assert {:ok, %SearchQuery{}} = SearchQuery.parse("")
      assert {:ok, %SearchQuery{}} = SearchQuery.parse("   ")
    end

    test "plain text is captured as free_text" do
      assert {:ok, %SearchQuery{free_text: "phoenix"}} = SearchQuery.parse("phoenix")
    end

    test "a single filter is captured" do
      assert {:ok, %SearchQuery{build_tools: ["mix"]}} = SearchQuery.parse("build_tool:mix")
    end

    test "mixed free text and filters" do
      {:ok, q} = SearchQuery.parse("phoenix build_tool:mix depends:ecto")
      assert q.free_text == "phoenix"
      assert q.build_tools == ["mix"]
      assert q.depends == "ecto"
    end

    test "repeated build_tool filters accumulate" do
      {:ok, q} = SearchQuery.parse("build_tool:mix build_tool:rebar3")
      assert q.build_tools == ["mix", "rebar3"]
    end

    test "repeated extra filters accumulate as {key, value} tuples" do
      {:ok, q} = SearchQuery.parse("extra:license,MIT extra:maintenance,active")
      assert q.extra == [{"license", "MIT"}, {"maintenance", "active"}]
    end

    test "quoted values preserve spaces" do
      {:ok, q} = SearchQuery.parse(~s(name:"my package" build_tool:mix))
      assert q.name == "my package"
      assert q.build_tools == ["mix"]
    end

    test "unknown filter operators round-trip via :unknown" do
      {:ok, q} = SearchQuery.parse("foo:bar build_tool:mix")
      assert q.unknown == [{"foo", "bar"}]
      assert q.build_tools == ["mix"]
    end

    test "malformed extra value returns an error" do
      assert {:error, {:extra, _}} = SearchQuery.parse("extra:no_comma_here")
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
mix test test/hexpm/repository/package/search_query_test.exs
```

Expected: all tests fail (module raises "not implemented").

- [ ] **Step 4: Commit the failing tests**

```bash
git add lib/hexpm/repository/package/search_query.ex test/hexpm/repository/package/search_query_test.exs
git commit -m "Add failing SearchQuery parse tests"
```

---

## Task 2: SearchQuery parse — implementation

**Files:**
- Modify: `lib/hexpm/repository/package/search_query.ex`

- [ ] **Step 1: Implement `parse/1`**

Write tokens by splitting on whitespace while respecting `"quoted values"`. For each token, if it matches `key:value`, dispatch into the struct; otherwise treat as free text (concatenated with spaces).

```elixir
defmodule Hexpm.Repository.Package.SearchQuery do
  @moduledoc """
  Parses and serializes hexpm package search strings into a structured form.

  Supports mixed free-text and `key:value` filter tokens. Unknown filter keys
  are preserved via the `:unknown` field so they round-trip through parse/serialize.
  """

  defstruct free_text: nil,
            depends: nil,
            build_tools: [],
            updated_after: nil,
            extra: [],
            name: nil,
            description: nil,
            unknown: []

  @type t :: %__MODULE__{}

  @known_keys ~w(name description depends build_tool updated_after extra)

  @spec parse(String.t() | nil) :: {:ok, t()} | {:error, term()}
  def parse(nil), do: {:ok, %__MODULE__{}}

  def parse(string) when is_binary(string) do
    string
    |> tokenize()
    |> Enum.reduce_while({:ok, %__MODULE__{}, []}, fn token, {:ok, acc, text} ->
      case apply_token(token, acc) do
        {:ok, acc} -> {:cont, {:ok, acc, text}}
        {:text, word} -> {:cont, {:ok, acc, [word | text]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc, text} ->
        free_text = text |> Enum.reverse() |> Enum.join(" ") |> nil_if_empty()
        {:ok, %{acc | free_text: free_text, extra: Enum.reverse(acc.extra),
                     build_tools: Enum.reverse(acc.build_tools),
                     unknown: Enum.reverse(acc.unknown)}}

      {:error, _} = err ->
        err
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp apply_token({:word, w}, _acc), do: {:text, w}

  defp apply_token({:pair, "name", v}, acc), do: {:ok, %{acc | name: v}}
  defp apply_token({:pair, "description", v}, acc), do: {:ok, %{acc | description: v}}
  defp apply_token({:pair, "depends", v}, acc), do: {:ok, %{acc | depends: v}}
  defp apply_token({:pair, "updated_after", v}, acc), do: {:ok, %{acc | updated_after: v}}

  defp apply_token({:pair, "build_tool", v}, acc) do
    {:ok, %{acc | build_tools: [v | acc.build_tools]}}
  end

  defp apply_token({:pair, "extra", v}, acc) do
    case String.split(v, ",", parts: 2) do
      [key, value] when key != "" -> {:ok, %{acc | extra: [{key, value} | acc.extra]}}
      _ -> {:error, {:extra, v}}
    end
  end

  defp apply_token({:pair, key, v}, acc) when key not in @known_keys do
    {:ok, %{acc | unknown: [{key, v} | acc.unknown]}}
  end

  # --- tokenizer ---

  defp tokenize(string) do
    string
    |> String.trim()
    |> do_tokenize([])
    |> Enum.reverse()
  end

  defp do_tokenize("", acc), do: acc

  defp do_tokenize(string, acc) do
    string = String.trim_leading(string)

    cond do
      string == "" ->
        acc

      (colon_index = colon_before_space(string)) != nil ->
        {key, rest} = String.split_at(string, colon_index)
        {:ok, value, rest_after} = read_value(String.slice(rest, 1..-1//1))
        do_tokenize(rest_after, [{:pair, key, value} | acc])

      true ->
        {word, rest} = read_word(string)
        do_tokenize(rest, [{:word, word} | acc])
    end
  end

  defp colon_before_space(string) do
    case :binary.match(string, ":") do
      {colon, _} ->
        case :binary.match(string, " ") do
          {space, _} when space < colon -> nil
          _ -> colon
        end

      :nomatch ->
        nil
    end
  end

  defp read_value(<<?", rest::binary>>) do
    case String.split(rest, "\"", parts: 2) do
      [value, tail] -> {:ok, value, String.trim_leading(tail)}
      [value] -> {:ok, value, ""}
    end
  end

  defp read_value(string) do
    {word, rest} = read_word(string)
    {:ok, word, rest}
  end

  defp read_word(string) do
    case String.split(string, " ", parts: 2) do
      [word] -> {word, ""}
      [word, tail] -> {word, String.trim_leading(tail)}
    end
  end

  # --- serialize stub until Task 3 ---

  def serialize(_query), do: raise("not implemented")
end
```

- [ ] **Step 2: Run parse tests**

```bash
mix test test/hexpm/repository/package/search_query_test.exs
```

Expected: all parse tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/hexpm/repository/package/search_query.ex
git commit -m "Implement SearchQuery parse"
```

---

## Task 3: SearchQuery serialize — tests and implementation

**Files:**
- Modify: `lib/hexpm/repository/package/search_query.ex`
- Modify: `test/hexpm/repository/package/search_query_test.exs`

- [ ] **Step 1: Append serialize tests**

```elixir
  describe "serialize/1" do
    alias Hexpm.Repository.Package.SearchQuery

    test "empty query serializes to empty string" do
      assert SearchQuery.serialize(%SearchQuery{}) == ""
    end

    test "free text only" do
      assert SearchQuery.serialize(%SearchQuery{free_text: "phoenix"}) == "phoenix"
    end

    test "filters serialize in canonical order: free_text, name, description, depends, build_tools, updated_after, extra, unknown" do
      q = %SearchQuery{
        free_text: "phoenix",
        build_tools: ["mix", "rebar3"],
        depends: "ecto",
        updated_after: "2025-01-01T00:00:00Z",
        extra: [{"license", "MIT"}]
      }

      assert SearchQuery.serialize(q) ==
               "phoenix depends:ecto build_tool:mix build_tool:rebar3 updated_after:2025-01-01T00:00:00Z extra:license,MIT"
    end

    test "quotes values containing spaces" do
      q = %SearchQuery{name: "my package"}
      assert SearchQuery.serialize(q) == ~s(name:"my package")
    end

    test "parse ∘ serialize is identity for supported fields" do
      input = "phoenix depends:ecto build_tool:mix build_tool:rebar3 extra:license,MIT"
      {:ok, q} = SearchQuery.parse(input)
      assert SearchQuery.serialize(q) == input
    end

    test "unknown keys round-trip" do
      {:ok, q} = SearchQuery.parse("foo:bar build_tool:mix")
      assert SearchQuery.serialize(q) == "build_tool:mix foo:bar"
    end
  end
```

- [ ] **Step 2: Replace the serialize stub**

In `lib/hexpm/repository/package/search_query.ex`, replace the `serialize/1` stub:

```elixir
  @spec serialize(t()) :: String.t()
  def serialize(%__MODULE__{} = q) do
    [
      q.free_text,
      pair("name", q.name),
      pair("description", q.description),
      pair("depends", q.depends),
      Enum.map(q.build_tools, &pair("build_tool", &1)),
      pair("updated_after", q.updated_after),
      Enum.map(q.extra, fn {k, v} -> pair("extra", "#{k},#{v}") end),
      Enum.map(q.unknown, fn {k, v} -> pair(k, v) end)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp pair(_key, nil), do: nil
  defp pair(_key, ""), do: nil

  defp pair(key, value) do
    if String.contains?(value, " "), do: ~s(#{key}:"#{value}"), else: "#{key}:#{value}"
  end
```

- [ ] **Step 3: Run tests**

```bash
mix test test/hexpm/repository/package/search_query_test.exs
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/hexpm/repository/package/search_query.ex test/hexpm/repository/package/search_query_test.exs
git commit -m "Implement SearchQuery serialize"
```

---

## Task 4: Multi-value build_tool OR semantics

Currently `search_param("build_tool", search, query)` in `lib/hexpm/repository/package.ex:298` ANDs repeated build_tool filters. Checkbox facets need OR.

**Files:**
- Modify: `lib/hexpm/repository/package.ex:298-309`
- Modify: `test/hexpm/repository/package_test.exs:300-331` (the existing `"package search with build_tool"` test — add an OR case)

- [ ] **Step 1: Write failing test for OR semantics**

In `test/hexpm/repository/package_test.exs`, add inside the same `describe` block that already contains the `build_tool:mix` test (around line 330):

```elixir
  test "build_tool filter OR-combines multiple values", %{repository: repository} do
    ecto = insert(:package, name: "ecto_or", repository_id: repository.id)
    insert(:release, package: ecto, meta: build(:release_metadata, build_tools: ["mix"]))

    benchee = insert(:package, name: "benchee_or", repository_id: repository.id)
    insert(:release, package: benchee, meta: build(:release_metadata, build_tools: ["rebar3"]))

    gleam_pkg = insert(:package, name: "gleam_pkg_or", repository_id: repository.id)
    insert(:release, package: gleam_pkg, meta: build(:release_metadata, build_tools: ["gleam"]))

    results = search_for(repository, "build_tool:mix build_tool:rebar3")
    assert "ecto_or" in results
    assert "benchee_or" in results
    refute "gleam_pkg_or" in results
  end
```

- [ ] **Step 2: Run test, verify it fails**

```bash
mix test test/hexpm/repository/package_test.exs -k "OR-combines"
```

Expected: fail — today's code ANDs the filters so only packages with both tools pass.

- [ ] **Step 3: Patch `search_param`**

Replace the existing clause:

```elixir
  defp search_param("build_tool", search, query) do
    # go with a sub-query because a join would add multiples and distinct mucks with sort order
    from(p in query,
      where:
        exists(
          from(r in Release,
            where: r.package_id == parent_as(:package).id,
            where: fragment("?->'build_tools' @> ?", r.meta, ^search)
          )
        )
    )
  end
```

The existing callsite passes a single string per filter occurrence. Because `parse_search` emits one `{key, value}` per token, repeated `build_tool:` tokens call `search_param` multiple times. We accumulate *inside* search_param by emitting an array-overlap clause against a list that grows across calls. Simplest approach: coalesce repeated calls by tracking state in `Ecto.Query`'s `where` clauses — but that would force AND.

The cleaner route: pre-aggregate in `search/2` (line 205-213). Change:

```elixir
  defp search(query, search) when is_binary(search) do
    case parse_search(search) do
      {:ok, params} ->
        params
        |> group_build_tools()
        |> Enum.reduce(query, fn {k, v}, q -> search_param(k, v, q) end)

      :error ->
        basic_search(query, search)
    end
  end

  defp group_build_tools(params) do
    {tools, rest} = Enum.split_with(params, fn {k, _} -> k == "build_tool" end)
    case tools do
      [] -> rest
      [single] -> rest ++ [single]
      _ -> rest ++ [{"build_tool", Enum.map(tools, fn {_, v} -> v end)}]
    end
  end
```

Then extend `search_param("build_tool", ...)` to accept both a string and a list:

```elixir
  defp search_param("build_tool", values, query) when is_list(values) do
    from(p in query,
      where:
        exists(
          from(r in Release,
            where: r.package_id == parent_as(:package).id,
            where: fragment("?->'build_tools' ?| ?", r.meta, ^values)
          )
        )
    )
  end

  defp search_param("build_tool", search, query) when is_binary(search) do
    search_param("build_tool", [search], query)
  end
```

The `?|` operator is "array/text array overlap with jsonb array of strings" — it returns true if the jsonb array contains any of the provided strings. (PostgreSQL: `jsonb ?| text[]`.)

- [ ] **Step 4: Run build_tool tests**

```bash
mix test test/hexpm/repository/package_test.exs -k "build_tool"
```

Expected: new OR test passes; pre-existing single-value build_tool tests still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/hexpm/repository/package.ex test/hexpm/repository/package_test.exs
git commit -m "Support multi-value build_tool filter with OR semantics"
```

---

## Task 5: Add live_view helper and live_session route

**Files:**
- Modify: `lib/hexpm_web/web.ex`
- Modify: `lib/hexpm_web/router.ex:184`
- Create: `lib/hexpm_web/live/package_live/index.ex`

- [ ] **Step 1: Add `live_view/0` helper to `HexpmWeb`**

In `lib/hexpm_web/web.ex`, add after the `view/0` function (before `router/0`):

```elixir
  def live_view() do
    quote do
      use Phoenix.LiveView, layout: {HexpmWeb.LayoutView, :app}

      import Phoenix.HTML
      import Phoenix.HTML.Form
      import HexpmWeb.ViewIcons
      import HexpmWeb.Components.Buttons
      import HexpmWeb.Components.Input
      import HexpmWeb.Components.Modal
      import HexpmWeb.Components.Package
      alias HexpmWeb.ViewHelpers
      use Hexpm.Shared

      unquote(verified_routes())
    end
  end
```

Note: `HexpmWeb.LayoutView` already renders `app.html.heex` for controllers. Using the same layout tuple reuses the app chrome (navbar, footer) for the LiveView.

- [ ] **Step 2: Scaffold `PackageLive.Index`**

```elixir
# lib/hexpm_web/live/package_live/index.ex
defmodule HexpmWeb.PackageLive.Index do
  use HexpmWeb, :live_view

  alias Hexpm.Repository.Package.SearchQuery

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, title: "Packages", container: "container")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:ok, _query} = SearchQuery.parse(params["search"])
    {:noreply, assign(socket, params: params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <h1 class="text-4xl font-bold">Packages (LiveView scaffold)</h1>
      <p>Params: <code>{inspect(@params)}</code></p>
    </div>
    """
  end
end
```

- [ ] **Step 3: Add an on_mount module that assigns `current_user` from the session**

The `/packages` page is public but uses `current_user` to include packages from private repositories the user can see. Create a tiny on_mount hook so the LiveView has the same signal the controller had via `conn.assigns.current_user`.

```elixir
# lib/hexpm_web/live/init_assigns.ex
defmodule HexpmWeb.Live.InitAssigns do
  import Phoenix.Component, only: [assign_new: 3]

  def on_mount(:default, _params, session, socket) do
    current_user =
      case session["user_id"] do
        nil -> nil
        id -> Hexpm.Accounts.Users.get_by_id(id)
      end

    {:cont, assign_new(socket, :current_user, fn -> current_user end)}
  end
end
```

Verify the session key `"user_id"` matches what hexpm actually stores. Grep:

```bash
grep -rn "put_session\|:user_id" lib/hexpm_web/
```

If hexpm stores the user under a different key (e.g. `"user"`), adjust the lookup accordingly.

- [ ] **Step 4: Replace the controller index route with a live route**

In `lib/hexpm_web/router.ex`, replace line 184:

```elixir
    get "/packages", PackageController, :index
```

with:

```elixir
    live_session :packages, on_mount: {HexpmWeb.Live.InitAssigns, :default} do
      live "/packages", PackageLive.Index, :index
    end
```

- [ ] **Step 5: Compile and load `/packages`**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile.

Start the dev server (`iex -S mix phx.server`) and open `/packages` in a browser. Expected: scaffold heading renders with no JS console errors.

- [ ] **Step 6: Commit**

```bash
git add lib/hexpm_web/web.ex lib/hexpm_web/router.ex \
        lib/hexpm_web/live/init_assigns.ex \
        lib/hexpm_web/live/package_live/index.ex
git commit -m "Scaffold PackageLive.Index and swap /packages to a live route"
```

---

## Task 6: Port controller logic into LiveView (feature parity)

This task achieves complete feature parity with the old controller action, with no filter UI yet. The existing template moves into the LiveView.

**Files:**
- Modify: `lib/hexpm_web/live/package_live/index.ex`
- Delete: `lib/hexpm_web/templates/package/index.html.heex`
- Modify: `lib/hexpm_web/controllers/package_controller.ex` — remove `index/2`, `fetch_packages/5`, `exact_match/2`, and `sort/1` (if no longer used; verify with `grep`).
- Create: `test/hexpm_web/live/package_live/index_test.exs`

- [ ] **Step 1: Write a failing LiveView mount test**

```elixir
# test/hexpm_web/live/package_live/index_test.exs
defmodule HexpmWeb.PackageLive.IndexTest do
  use HexpmWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    repository = Hexpm.Repository.Repositories.get("hexpm")
    insert(:package, name: "phoenix_test_pkg", repository_id: repository.id)
    insert(:package, name: "ecto_test_pkg", repository_id: repository.id)
    :ok
  end

  test "renders package list", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/packages")
    assert html =~ "Packages"
    assert html =~ "phoenix_test_pkg"
    assert html =~ "ecto_test_pkg"
  end

  test "filters by search param", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/packages?search=phoenix_test_pkg")
    assert html =~ "phoenix_test_pkg"
    refute html =~ "ecto_test_pkg"
  end

  test "honors sort param", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/packages?sort=name")
    assert html =~ "ecto_test_pkg"
  end
end
```

- [ ] **Step 2: Run the new test, verify it fails**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs
```

Expected: fails because scaffold renders no packages.

- [ ] **Step 3: Port the controller logic into the LiveView**

Move the data-loading from `PackageController.index/2` into the LiveView. Move the HEEx from `templates/package/index.html.heex` into `render/1` (or split out to a co-located `index.html.heex` via the `~H` sigil + `Phoenix.Component.embed_templates/1`). Simplest: inline into `render/1`.

```elixir
defmodule HexpmWeb.PackageLive.Index do
  use HexpmWeb, :live_view

  alias Hexpm.{Packages, Users}
  alias Hexpm.Accounts.Downloads
  alias Hexpm.Repository.Package.SearchQuery

  @packages_per_page 30
  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at)
  @letters for letter <- ?A..?Z, do: <<letter>>

  @impl true
  def mount(_params, _session, socket) do
    # :current_user already assigned by HexpmWeb.Live.InitAssigns on_mount hook.
    organizations = Users.all_organizations(socket.assigns.current_user)
    repositories = Enum.map(organizations, & &1.repository)

    {:ok,
     socket
     |> assign(
       title: "Packages",
       container: "container",
       per_page: @packages_per_page,
       letters: @letters,
       repositories: repositories,
       depends_suggestions: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_results(socket, params)}
  end

  defp load_results(socket, params) do
    repositories = socket.assigns.repositories
    letter = Hexpm.Utils.parse_search(params["letter"])
    search = Hexpm.Utils.parse_search(params["search"])

    filter =
      cond do
        letter -> {:letter, letter}
        search -> search
        true -> nil
      end

    sort = sort(params["sort"])
    page_param = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(repositories, filter)
    page = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    exact_match = exact_match(repositories, search)

    all_matches =
      repositories
      |> Packages.search(page, @packages_per_page, filter, sort, nil)
      |> Packages.attach_latest_releases()

    downloads =
      Downloads.packages_all_views(Enum.reject([exact_match | all_matches], &is_nil/1))

    packages = Packages.diff(all_matches, exact_match)
    {:ok, search_query} = SearchQuery.parse(search)

    assign(socket,
      search: search,
      search_query: search_query,
      letter: letter,
      sort: sort,
      package_count: package_count,
      page: page,
      packages: packages,
      downloads: downloads,
      exact_match: exact_match
    )
  end

  @impl true
  def render(assigns) do
    # Paste the contents of the old templates/package/index.html.heex here,
    # verbatim except for assigns access (they are already `@search`, `@packages`, etc.).
    # Wrap in ~H""" ... """.
    ~H"""
    ... (copy from lib/hexpm_web/templates/package/index.html.heex) ...
    """
  end

  defp sort(nil), do: sort("recent_downloads")
  defp sort("downloads"), do: sort("recent_downloads")
  defp sort(param), do: Hexpm.Utils.safe_to_atom(param, @sort_params)

  defp exact_match(_repositories, nil), do: nil

  defp exact_match(repositories, search) do
    # Same body as PackageController.exact_match/2
    search
    |> String.replace(" ", "_")
    |> String.split("/", parts: 2)
    |> case do
      [repository, package] ->
        if repository in Enum.map(repositories, & &1.name),
          do: Packages.get(repository, package)

      [term] ->
        try do
          Packages.get(repositories, term)
        rescue
          Ecto.MultipleResultsError -> nil
        end
    end
    |> case do
      nil -> nil
      package -> [package] = Packages.attach_latest_releases([package]); package
    end
  end
end
```

- [ ] **Step 4: Delete the old template and controller action**

```bash
rm lib/hexpm_web/templates/package/index.html.heex
```

In `lib/hexpm_web/controllers/package_controller.ex`: delete `index/2` (lines 9-52) and the private helpers it exclusively used: `fetch_packages/5` (lines 368-372), `exact_match/2` (lines 374-404). Keep `sort/1`, `current_release/1`, `access_package/3`, `matching_release/2`, `package/6`, `sidebar_assigns/3`, `fixup_params/1` — `show/dependencies/dependents/versions/audit_logs` still use them.

Check with:
```bash
grep -n "fetch_packages\|exact_match\|index\(" lib/hexpm_web/controllers/package_controller.ex
```
Expected: no matches (only `audit_logs` remains from the `index` family).

- [ ] **Step 5: Run LiveView tests**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs
```

Expected: all pass.

- [ ] **Step 6: Run the full web test suite**

```bash
mix test test/hexpm_web
```

Expected: all pass. If `package_controller_test.exs` has tests for `:index`, port them to the new LiveView test or delete — flag to reviewer in the commit message.

- [ ] **Step 7: Commit**

```bash
git add -A lib/hexpm_web/live/package_live/index.ex \
         lib/hexpm_web/controllers/package_controller.ex \
         lib/hexpm_web/templates/package/index.html.heex \
         test/hexpm_web/live/package_live/index_test.exs
git commit -m "Port /packages index to LiveView with full feature parity"
```

---

## Task 7: FilterSidebar component — build_tool checkboxes

**Files:**
- Create: `lib/hexpm_web/live/package_live/filter_sidebar.ex`
- Modify: `lib/hexpm_web/live/package_live/index.ex` (render sidebar + handle_event)
- Modify: `test/hexpm_web/live/package_live/index_test.exs`

**Known build tools for v1:** `["mix", "rebar3", "make", "gleam"]` — `gleam` appears in `test/hexpm/repository/package_test.exs:313`, the other three are standard. If the reviewer wants a dynamic list, flag in the PR; do not block on this.

- [ ] **Step 1: Create the sidebar component**

```elixir
# lib/hexpm_web/live/package_live/filter_sidebar.ex
defmodule HexpmWeb.PackageLive.FilterSidebar do
  use Phoenix.Component

  alias Hexpm.Repository.Package.SearchQuery

  @build_tools ~w(mix rebar3 make gleam)

  attr :query, SearchQuery, required: true

  def sidebar(assigns) do
    assigns = assign(assigns, :build_tools, @build_tools)

    ~H"""
    <aside class="w-56 shrink-0" aria-label="Filters">
      <form phx-change="filter_change" id="filter-form">
        <h3 class="font-semibold text-grey-900 dark:text-grey-100 mb-3">Filters</h3>

        <fieldset class="mb-6">
          <legend class="text-sm font-medium mb-2">Build tool</legend>
          <div class="space-y-1">
            <label :for={tool <- @build_tools} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                name={"build_tool[#{tool}]"}
                value="true"
                checked={tool in @query.build_tools}
              />
              <span>{tool}</span>
            </label>
          </div>
        </fieldset>
      </form>
    </aside>
    """
  end
end
```

- [ ] **Step 2: Wire the sidebar into the LiveView layout**

In `lib/hexpm_web/live/package_live/index.ex`, import the component and change the results section of `render/1` to a flex row with the sidebar on the left:

```elixir
  import HexpmWeb.PackageLive.FilterSidebar
```

Inside the template, wrap the results area:

```heex
<div class="flex gap-6">
  <.sidebar query={@search_query} />
  <div class="flex-1 min-w-0">
    <%!-- existing results list unchanged --%>
  </div>
</div>
```

Hide the sidebar when `@letter` is set (matches the current A–Z browsing flow):

```heex
<div :if={is_nil(@letter)} class="flex gap-6">
  <.sidebar query={@search_query} />
  <div class="flex-1 min-w-0">
    ...
  </div>
</div>
<div :if={@letter}>
  ...
</div>
```

- [ ] **Step 3: Handle `filter_change` events**

Add to `PackageLive.Index`:

```elixir
  @impl true
  def handle_event("filter_change", params, socket) do
    build_tools =
      params
      |> Map.get("build_tool", %{})
      |> Enum.filter(fn {_, v} -> v == "true" end)
      |> Enum.map(fn {k, _} -> k end)
      |> Enum.sort()

    new_query = %{socket.assigns.search_query | build_tools: build_tools}
    new_search = SearchQuery.serialize(new_query)

    params =
      socket.assigns
      |> Map.take([:sort])
      |> Map.put(:search, nil_if_empty(new_search))
      |> Map.put(:page, nil)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/packages?#{params}")}
  end

  defp nil_if_empty(nil), do: nil
  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s
```

- [ ] **Step 4: Add a LiveView test for checkbox interaction**

Append to `test/hexpm_web/live/package_live/index_test.exs`:

```elixir
  describe "build_tool checkbox" do
    setup do
      repository = Hexpm.Repository.Repositories.get("hexpm")
      mix_pkg = insert(:package, name: "mix_only", repository_id: repository.id)
      insert(:release, package: mix_pkg, meta: build(:release_metadata, build_tools: ["mix"]))

      rebar_pkg = insert(:package, name: "rebar_only", repository_id: repository.id)
      insert(:release, package: rebar_pkg, meta: build(:release_metadata, build_tools: ["rebar3"]))

      :ok
    end

    test "ticking a build_tool patches URL and narrows results", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/packages")
      assert render(view) =~ "mix_only"
      assert render(view) =~ "rebar_only"

      view
      |> form("#filter-form", %{"build_tool" => %{"mix" => "true"}})
      |> render_change()

      assert_patch(view, ~p"/packages?search=build_tool%3Amix")
      html = render(view)
      assert html =~ "mix_only"
      refute html =~ "rebar_only"
    end
  end
```

- [ ] **Step 5: Run tests**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/hexpm_web/live/package_live/filter_sidebar.ex \
        lib/hexpm_web/live/package_live/index.ex \
        test/hexpm_web/live/package_live/index_test.exs
git commit -m "Add FilterSidebar with build_tool checkboxes"
```

---

## Task 8: Depends filter + autocomplete

**Files:**
- Modify: `lib/hexpm/repository/package.ex` (add `search_by_prefix/2`)
- Modify: `lib/hexpm_web/live/package_live/filter_sidebar.ex`
- Modify: `lib/hexpm_web/live/package_live/index.ex`

- [ ] **Step 1: Add `Package.search_by_prefix/2` with a test**

Append to `test/hexpm/repository/package_test.exs` (inside the same describe block that exercises `search_for`):

```elixir
  test "search_by_prefix returns up to 10 public packages matching a prefix", %{repository: repository} do
    for name <- ~w(phx1 phx2 phx3 phx4 phx5 phx6 phx7 phx8 phx9 phx10 phx11) do
      insert(:package, name: name, repository_id: repository.id)
    end

    results = Hexpm.Repository.Package.search_by_prefix([repository], "phx")
    assert length(results) == 10
    assert Enum.all?(results, &String.starts_with?(&1.name, "phx"))
  end
```

In `lib/hexpm/repository/package.ex`, add a public function:

```elixir
  @doc """
  Returns up to 10 packages whose names start with `prefix` within the given repositories.
  Used by the sidebar depends-filter autocomplete.
  """
  def search_by_prefix(repositories, prefix) when is_binary(prefix) and prefix != "" do
    repo_ids = Enum.map(repositories, & &1.id)
    pattern = String.downcase(prefix) <> "%"

    from(p in __MODULE__,
      where: p.repository_id in ^repo_ids,
      where: like(fragment("lower(?)", p.name), ^pattern),
      order_by: [asc: p.name],
      limit: 10
    )
    |> Hexpm.Repo.all()
    |> Hexpm.Repo.preload(:repository)
  end

  def search_by_prefix(_repositories, _), do: []
```

- [ ] **Step 2: Run the new test**

```bash
mix test test/hexpm/repository/package_test.exs -k "search_by_prefix"
```

Expected: pass.

- [ ] **Step 3: Add the depends input + autocomplete to the sidebar**

In `lib/hexpm_web/live/package_live/filter_sidebar.ex`, add another fieldset after Build tool:

```heex
<fieldset class="mb-6">
  <legend class="text-sm font-medium mb-2">Depends on</legend>
  <input
    type="text"
    name="depends"
    value={@query.depends || ""}
    list="depends-suggestions"
    placeholder="package name"
    phx-debounce="300"
    class="w-full px-2 py-1 border rounded"
  />
  <datalist id="depends-suggestions">
    <option :for={name <- @depends_suggestions} value={name} />
  </datalist>
</fieldset>
```

Add a `:depends_suggestions` attr:

```elixir
  attr :depends_suggestions, :list, default: []
```

- [ ] **Step 4: Wire autocomplete in the LiveView**

In `PackageLive.Index`, extend `handle_event("filter_change", ...)` to also read `depends` from params and rebuild `%SearchQuery{}`:

```elixir
  def handle_event("filter_change", params, socket) do
    build_tools = checked(params, "build_tool")
    depends = nil_if_empty(params["depends"])

    new_query = %{socket.assigns.search_query | build_tools: build_tools, depends: depends}
    suggestions =
      if depends, do: suggestions_for(depends, socket.assigns.repositories), else: []

    socket = assign(socket, depends_suggestions: suggestions)

    new_search = SearchQuery.serialize(new_query)
    params = url_params(socket, new_search)
    {:noreply, push_patch(socket, to: ~p"/packages?#{params}")}
  end

  defp checked(params, key) do
    params
    |> Map.get(key, %{})
    |> Enum.filter(fn {_, v} -> v == "true" end)
    |> Enum.map(fn {k, _} -> k end)
    |> Enum.sort()
  end

  defp suggestions_for(prefix, repositories) do
    repositories
    |> Hexpm.Repository.Package.search_by_prefix(prefix)
    |> Enum.map(& &1.name)
  end

  defp url_params(socket, new_search) do
    %{sort: socket.assigns.sort, search: nil_if_empty(new_search)}
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end
```

Initialize `depends_suggestions: []` in `mount/3`. Pass it through to the sidebar: `<.sidebar query={@search_query} depends_suggestions={@depends_suggestions} />`.

- [ ] **Step 5: Write a LiveView test**

```elixir
  test "typing in depends filter narrows results", %{conn: conn} do
    repository = Hexpm.Repository.Repositories.get("hexpm")
    ecto = insert(:package, name: "ecto_dep_src", repository_id: repository.id)
    insert(:package, name: "postgrex_dep_src", repository_id: repository.id)

    consumer = insert(:package, name: "ecto_consumer", repository_id: repository.id)
    release = insert(:release, package: consumer)
    insert(:requirement, release: release, dependency: ecto, requirement: "~> 1.0")

    {:ok, view, _} = live(conn, ~p"/packages")

    view
    |> form("#filter-form", %{"depends" => "ecto_dep_src"})
    |> render_change()

    html = render(view)
    assert html =~ "ecto_consumer"
    refute html =~ "postgrex_dep_src"
  end
```

- [ ] **Step 6: Run tests**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs test/hexpm/repository/package_test.exs
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/hexpm/repository/package.ex \
        lib/hexpm_web/live/package_live/filter_sidebar.ex \
        lib/hexpm_web/live/package_live/index.ex \
        test/hexpm/repository/package_test.exs \
        test/hexpm_web/live/package_live/index_test.exs
git commit -m "Add depends filter with autocomplete to package sidebar"
```

---

## Task 9: Updated after date filter

**Files:**
- Modify: `lib/hexpm_web/live/package_live/filter_sidebar.ex`
- Modify: `lib/hexpm_web/live/package_live/index.ex`
- Modify: `test/hexpm_web/live/package_live/index_test.exs`

- [ ] **Step 1: Add fieldset to sidebar**

```heex
<fieldset class="mb-6">
  <legend class="text-sm font-medium mb-2">Updated after</legend>
  <input
    type="date"
    name="updated_after"
    value={date_value(@query.updated_after)}
    class="w-full px-2 py-1 border rounded"
  />
</fieldset>
```

Helper in the same module:

```elixir
  defp date_value(nil), do: ""
  defp date_value(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> Date.to_iso8601(DateTime.to_date(dt))
      _ -> ""
    end
  end
```

- [ ] **Step 2: Handle `updated_after` in `filter_change`**

In `handle_event/3`:

```elixir
    updated_after =
      case params["updated_after"] do
        nil -> nil
        "" -> nil
        date_string -> "#{date_string}T00:00:00Z"
      end

    new_query = %{new_query | updated_after: updated_after}
```

- [ ] **Step 3: Add test**

```elixir
  test "updated_after filter narrows by date", %{conn: conn} do
    repository = Hexpm.Repository.Repositories.get("hexpm")
    old = insert(:package, name: "old_pkg", repository_id: repository.id,
                          updated_at: ~U[2020-01-01 00:00:00Z])
    new = insert(:package, name: "new_pkg", repository_id: repository.id,
                          updated_at: ~U[2025-06-01 00:00:00Z])

    {:ok, view, _} = live(conn, ~p"/packages")

    view
    |> form("#filter-form", %{"updated_after" => "2024-01-01"})
    |> render_change()

    html = render(view)
    assert html =~ "new_pkg"
    refute html =~ "old_pkg"
  end
```

- [ ] **Step 4: Run tests and commit**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs
```

```bash
git add lib/hexpm_web/live/package_live/filter_sidebar.ex \
        lib/hexpm_web/live/package_live/index.ex \
        test/hexpm_web/live/package_live/index_test.exs
git commit -m "Add updated_after date filter to package sidebar"
```

---

## Task 10: Extra key/value filter rows

**Files:**
- Modify: `lib/hexpm_web/live/package_live/filter_sidebar.ex`
- Modify: `lib/hexpm_web/live/package_live/index.ex`
- Modify: `test/hexpm_web/live/package_live/index_test.exs`

- [ ] **Step 1: Render rows**

In the sidebar, add a fieldset that renders one row per `{key, value}` in `@query.extra`, plus one blank row:

```heex
<fieldset class="mb-6">
  <legend class="text-sm font-medium mb-2">Extra metadata</legend>
  <div class="space-y-2">
    <div :for={{{k, v}, idx} <- Enum.with_index(@query.extra ++ [{"", ""}])}
         class="flex gap-1">
      <input type="text" name={"extra[#{idx}][key]"} value={k}
             placeholder="key" phx-debounce="300"
             class="w-1/2 px-2 py-1 border rounded text-sm" />
      <input type="text" name={"extra[#{idx}][value]"} value={v}
             placeholder="value" phx-debounce="300"
             class="w-1/2 px-2 py-1 border rounded text-sm" />
    </div>
  </div>
</fieldset>
```

The implicit blank row gives the user a way to add another pair without a dedicated button. When both fields are filled, submitting `filter_change` promotes it; the next render will include it in `@query.extra` plus a fresh blank row.

- [ ] **Step 2: Handle `extra` in `filter_change`**

```elixir
    extras =
      params
      |> Map.get("extra", %{})
      |> Map.values()
      |> Enum.map(fn %{"key" => k, "value" => v} -> {String.trim(k), String.trim(v)} end)
      |> Enum.reject(fn {k, v} -> k == "" or v == "" end)

    new_query = %{new_query | extra: extras}
```

- [ ] **Step 3: Test**

```elixir
  test "extra metadata filter narrows results", %{conn: conn} do
    repository = Hexpm.Repository.Repositories.get("hexpm")
    with_license =
      insert(:package, name: "licensed_pkg", repository_id: repository.id,
             meta: build(:package_metadata, extra: %{"license" => "MIT"}))

    insert(:package, name: "plain_pkg", repository_id: repository.id,
           meta: build(:package_metadata, extra: %{}))

    {:ok, view, _} = live(conn, ~p"/packages")

    view
    |> form("#filter-form", %{
      "extra" => %{"0" => %{"key" => "license", "value" => "MIT"}}
    })
    |> render_change()

    html = render(view)
    assert html =~ "licensed_pkg"
    refute html =~ "plain_pkg"
  end
```

(Adjust factory if `package_metadata` isn't the exact factory key — check `test/support/factory.ex`.)

- [ ] **Step 4: Run tests and commit**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs
```

```bash
git add lib/hexpm_web/live/package_live/filter_sidebar.ex \
        lib/hexpm_web/live/package_live/index.ex \
        test/hexpm_web/live/package_live/index_test.exs
git commit -m "Add extra metadata key/value filter rows to package sidebar"
```

---

## Task 11: Query preview strip and Clear all button

**Files:**
- Modify: `lib/hexpm_web/live/package_live/filter_sidebar.ex`
- Modify: `lib/hexpm_web/live/package_live/index.ex`
- Modify: `test/hexpm_web/live/package_live/index_test.exs`

- [ ] **Step 1: Render preview + clear button**

Append inside the sidebar `<form>`:

```heex
<div class="pt-4 border-t">
  <p class="text-xs text-grey-500 mb-1">Query</p>
  <pre class="text-xs font-mono bg-grey-50 dark:bg-grey-900 px-2 py-1 rounded break-words whitespace-pre-wrap">{@canonical_query}</pre>
  <button
    type="button"
    phx-click="clear_filters"
    class="mt-2 text-sm text-blue-600 hover:underline"
  >
    Clear all
  </button>
</div>
```

- [ ] **Step 2: Add `:canonical_query` attr + event handler**

In `FilterSidebar`: `attr :canonical_query, :string, default: ""`.

In `PackageLive.Index` `load_results/2`, after parsing the query:
```elixir
canonical_query = SearchQuery.serialize(search_query)
```
Assign it. Pass it to the sidebar.

Add handler:
```elixir
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/packages?#{%{sort: socket.assigns.sort}}")}
  end
```

- [ ] **Step 3: Test**

```elixir
  test "clear all resets the URL", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/packages?search=build_tool%3Amix")
    assert render(view) =~ "build_tool:mix"

    view |> element("button", "Clear all") |> render_click()
    assert_patch(view, ~p"/packages?sort=recent_downloads")
  end

  test "query preview shows the canonical serialized query", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/packages?search=build_tool%3Amix+depends%3Aecto")
    assert html =~ "depends:ecto build_tool:mix"
  end
```

- [ ] **Step 4: Run tests and commit**

```bash
mix test test/hexpm_web/live/package_live/index_test.exs
```

```bash
git add lib/hexpm_web/live/package_live/filter_sidebar.ex \
        lib/hexpm_web/live/package_live/index.ex \
        test/hexpm_web/live/package_live/index_test.exs
git commit -m "Add query preview strip and clear all to package sidebar"
```

---

## Task 12: FilterCheatsheet modal + navbar "?" trigger

**Files:**
- Create: `lib/hexpm_web/live/package_live/filter_cheatsheet.ex`
- Create: `test/hexpm_web/live/package_live/filter_cheatsheet_test.exs`
- Modify: `lib/hexpm_web/components/navbar.ex:293-317`
- Modify: `lib/hexpm_web/templates/layout/app.html.heex` (render the modal once)

- [ ] **Step 1: Write failing component render test**

```elixir
# test/hexpm_web/live/package_live/filter_cheatsheet_test.exs
defmodule HexpmWeb.PackageLive.FilterCheatsheetTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import HexpmWeb.PackageLive.FilterCheatsheet

  test "lists every filter operator with an example" do
    html = render_component(&cheatsheet/1, %{id: "sheet"})
    for op <- ~w(name: description: depends: build_tool: updated_after: extra:) do
      assert html =~ op, "missing #{op}"
    end
    assert html =~ "mix"
    assert html =~ "phoenix"
  end
end
```

- [ ] **Step 2: Implement the component**

```elixir
# lib/hexpm_web/live/package_live/filter_cheatsheet.ex
defmodule HexpmWeb.PackageLive.FilterCheatsheet do
  use Phoenix.Component

  import HexpmWeb.Components.Modal

  @filters [
    {"name:", "Match package (or repo/package) name", "name:phoenix"},
    {"description:", "Full-text search of package descriptions", "description:auth"},
    {"depends:", "Packages depending on a given package", "depends:ecto"},
    {"build_tool:", "Filter by build tool (repeat for OR)", "build_tool:mix"},
    {"updated_after:", "Packages updated after an ISO8601 datetime",
     "updated_after:2025-01-01T00:00:00Z"},
    {"extra:", "Match custom metadata (key,value)", "extra:license,MIT"}
  ]

  attr :id, :string, required: true

  def cheatsheet(assigns) do
    assigns = assign(assigns, :filters, @filters)

    ~H"""
    <.modal id={@id} title="Search filters">
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-3">
        Type any of these into the search box. They can be combined with free text.
      </p>
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b">
            <th class="py-1 pr-3">Operator</th>
            <th class="py-1 pr-3">Description</th>
            <th class="py-1">Example</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{op, desc, example} <- @filters} class="border-b last:border-b-0">
            <td class="py-1 pr-3 font-mono">{op}</td>
            <td class="py-1 pr-3">{desc}</td>
            <td class="py-1 font-mono">{example}</td>
          </tr>
        </tbody>
      </table>
    </.modal>
    """
  end
end
```

- [ ] **Step 3: Run the render test**

```bash
mix test test/hexpm_web/live/package_live/filter_cheatsheet_test.exs
```

Expected: pass.

- [ ] **Step 4: Add the `?` button next to the navbar search input**

In `lib/hexpm_web/components/navbar.ex`, edit `search_form/1` (line 296-317). Inside the `<form>`, after the hidden sort input, add:

```heex
<button
  type="button"
  phx-click={HexpmWeb.Components.Modal.show_modal("search-cheatsheet")}
  aria-label="Search filter cheatsheet"
  class="ml-2 px-2 py-1 text-grey-200 hover:text-white border border-grey-600 rounded text-sm"
>
  ?
</button>
```

- [ ] **Step 5: Render the modal once globally**

In `lib/hexpm_web/templates/layout/app.html.heex`, just before the closing `</body>` (or wherever makes sense for modals):

```heex
{HexpmWeb.PackageLive.FilterCheatsheet.cheatsheet(%{id: "search-cheatsheet"})}
```

Verify the module is imported or fully qualified.

- [ ] **Step 6: Start dev server and manually verify**

```bash
iex -S mix phx.server
```

Open any page; click `?` next to the search box; modal should open listing the six operators. Close it; reload `/packages` — sidebar still works.

- [ ] **Step 7: Commit**

```bash
git add lib/hexpm_web/live/package_live/filter_cheatsheet.ex \
        test/hexpm_web/live/package_live/filter_cheatsheet_test.exs \
        lib/hexpm_web/components/navbar.ex \
        lib/hexpm_web/templates/layout/app.html.heex
git commit -m "Add search filter cheatsheet modal triggered from navbar"
```

---

## Task 13: Mobile collapsible sidebar

**Files:**
- Modify: `lib/hexpm_web/live/package_live/filter_sidebar.ex`
- Modify: `lib/hexpm_web/live/package_live/index.ex`

- [ ] **Step 1: Add a mobile disclosure wrapper**

Wrap the sidebar contents so on mobile (`sm:` breakpoint and below) it's hidden by default and toggled by a button above the results.

In the LiveView render, above the flex container:

```heex
<button
  type="button"
  phx-click={JS.toggle(to: "#filter-sidebar")}
  class="md:hidden mb-2 px-3 py-1 border rounded text-sm"
>
  Filters
</button>
```

In `FilterSidebar.sidebar/1`, add `id="filter-sidebar"` to the `<aside>` and a `hidden md:block` class so it's shown on desktop, toggled on mobile:

```heex
<aside id="filter-sidebar" class="w-full md:w-56 shrink-0 hidden md:block" aria-label="Filters">
```

Import `alias Phoenix.LiveView.JS` in `PackageLive.Index` (already available via `use HexpmWeb, :live_view` if included there).

- [ ] **Step 2: Manual check in dev server**

```bash
iex -S mix phx.server
```

Resize window below `md` breakpoint (< 768px). Sidebar hidden; Filters button toggles it. Above `md`, sidebar always visible.

- [ ] **Step 3: Commit**

```bash
git add lib/hexpm_web/live/package_live/filter_sidebar.ex \
        lib/hexpm_web/live/package_live/index.ex
git commit -m "Collapse package filter sidebar on mobile"
```

---

## Task 14: Full suite + open-question resolution

- [ ] **Step 1: Run the complete test suite**

```bash
mix test
```

Expected: all green. If any unrelated test fails, investigate before proceeding.

- [ ] **Step 2: Run the formatter**

```bash
mix format
```

- [ ] **Step 3: Spec open-questions follow-up**

Review the spec's Open Questions (build_tool enum, depends autocomplete scope). Ensure the PR description calls out:

1. The build_tool list is currently hardcoded as `["mix", "rebar3", "make", "gleam"]` in `FilterSidebar`. Reviewer decides whether to move it to a shared constant or derive dynamically.
2. The `depends` autocomplete uses `search_by_prefix/2` scoped to the same `repositories` list the LiveView already loads for the current user — so private packages the user has access to are included. If the reviewer prefers public-only for v1, change the argument to `[Hexpm.Repository.Repositories.get("hexpm")]`.

- [ ] **Step 4: Confirm nothing regressed in the controller test file**

```bash
grep -n "def index\|/packages\"" lib/hexpm_web/controllers/package_controller.ex
```

Expected: no `def index`. No `~p"/packages"` references that require the controller action.

- [ ] **Step 5: Push branch**

```bash
git push -u origin ericmj/package-search-filter-ui
```

Then provide the PR creation link to the user (do not run `gh pr create` without explicit approval per CLAUDE.md).

---

## Self-review notes

- **Spec coverage check:**
  - Faceted sidebar on `/packages` — Tasks 7-11.
  - Cheatsheet help modal from navbar — Task 12.
  - `SearchQuery` parse/serialize — Tasks 1-3.
  - `build_tool` OR semantics backend change — Task 4.
  - LiveView conversion — Tasks 5-6.
  - Sort pill position unchanged — preserved in Task 6 template port.
  - Mobile collapsed sidebar — Task 13.
  - Testing strategy — covered per-task plus Task 14 final sweep.
- **Placeholders:** none — every code step shows the change. Where template bodies are copied verbatim (Task 6 Step 3 `render/1`), the source file path is given explicitly.
- **Type consistency:** `%SearchQuery{}` fields used consistently across tasks (`build_tools` list, `depends` string, `updated_after` ISO8601 string, `extra` list of tuples). `handle_event("filter_change", ...)` signature stays the same across Tasks 7-11; each task extends it rather than redefining.
