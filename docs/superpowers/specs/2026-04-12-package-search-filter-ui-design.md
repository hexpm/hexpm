# Package Search Filter UI — Design

**Date:** 2026-04-12

## Problem

hexpm's package search supports six filter operators — `name:`, `description:`, `depends:`, `build_tool:`, `updated_after:`, and `extra:` — parsed in `lib/hexpm/repository/package.ex`. None of these are discoverable from the UI; users only find them by reading source code. The search input in the navbar is a plain text box with no hint that structured filters exist.

## Goal

Make the filter syntax discoverable *and* usable without typing, while keeping the syntax itself canonical so power users can still type it directly and bookmarks/URLs keep working.

## Approach

Faceted filter sidebar on the `/packages` results page, paired with a cheatsheet help modal reachable from the navbar search box on every page. Sidebar controls serialize back into the existing `search` query param — the URL remains the source of truth, and the canonical filter string is visible to users so they learn the syntax as they click.

## Architecture

Convert the `/packages` index route to a Phoenix LiveView (`HexpmWeb.PackageLive.Index`). This introduces the first LiveView in hexpm — the project currently uses `Phoenix.Component` pervasively but has no LiveViews in the router. Accepting this precedent is deliberate.

Scope of the LiveView switch:

- **Flipped:** `GET /packages` (HTML index listing) only.
- **Unchanged:** the rest of `HexpmWeb.PackageController` (`:show`, `:audit_logs`, `:dependents`, `:dependencies`, `:versions`) stays as plain controller actions.
- **Unchanged:** API endpoints under `/api/packages` (`HexpmWeb.API.PackageController`) are a separate controller, not touched.

Router additions:

- A single `live_session :default` wrapping the live route.
- `live "/packages", PackageLive.Index, :index`.

Client-side:

- `assets/js/app.js` gains a LiveSocket import and `.connect()` call.
- No Alpine, Stimulus, or other new JS frameworks.

Server-side query logic (`Hexpm.Repository.Package.all/6`) is untouched except for one small change: `search_param("build_tool", ...)` is extended to accept multiple values with OR semantics (see Backend change below).

## Components

**New modules:**

- `HexpmWeb.PackageLive.Index` — the LiveView: `mount/3`, `handle_params/3`, `handle_event/3`, `render/1`.
- `HexpmWeb.PackageLive.FilterSidebar` — function component that renders the sidebar given a `%SearchQuery{}` struct.
- `HexpmWeb.PackageLive.FilterCheatsheet` — function component rendering the `?` modal contents. Reusable from the navbar on any page.

**New pure module:**

- `Hexpm.Repository.Package.SearchQuery` — parses a search string into a structured `%SearchQuery{}` and serializes it back. Replaces the implicit regex parsing currently inline in `Package.search_filter/3` by factoring parse/serialize into a testable unit. `Package.all/6` itself still accepts a plain string; the LiveView calls `SearchQuery.serialize/1` before handing off.

The struct holds: `free_text`, `depends`, `build_tools` (list), `updated_after`, `extra` (list of `{key, value}`), and preserves any filter operators the UI doesn't yet model so unknown filters pass through untouched.

## UI Layout

Results page (`/packages`) layout:

```
┌─ navbar [ search… ? ] ─────────────────────────────┐
├────────────────────────────────────────────────────┤
│ A–Z browser (hidden while searching)               │
│ ┌──────────────┬─────────────────────────────────┐ │
│ │ Filters      │ Sort: [Recent DLs] [Name] ...   │ │
│ │              │ 1,234 results                   │ │
│ │ Depends on   │                                 │ │
│ │ [_________]  │ [result row]                    │ │
│ │              │ [result row]                    │ │
│ │ Build tool   │ [result row]                    │ │
│ │ ☐ mix        │ ...                             │ │
│ │ ☐ rebar3     │ [pagination]                    │ │
│ │              │                                 │ │
│ │ Updated      │                                 │ │
│ │ after        │                                 │ │
│ │ [date]       │                                 │ │
│ │              │                                 │ │
│ │ Extra meta   │                                 │ │
│ │ [key] [val]  │                                 │ │
│ │ + add row    │                                 │ │
│ │              │                                 │ │
│ │ Query: mono  │                                 │ │
│ │ [clear all]  │                                 │ │
│ └──────────────┴─────────────────────────────────┘ │
└────────────────────────────────────────────────────┘
```

Sidebar controls:

- **Depends on** — text input with server-side autocomplete (dropdown of matching package names).
- **Build tool** — checkboxes for the known tool set (mix, rebar3, + any additional tools; see Open Questions).
- **Updated after** — native date input.
- **Extra** — rows of `[key] [value]` pairs with a `+ add row` button to allow multiple `extra:` filters.

Below the controls:

- **Query preview** — a monospace read-only strip showing the canonical serialized filter string. This is how casual users learn the syntax.
- **Clear all** button.

Sort pill selector stays above the results (unchanged position).

Mobile: the sidebar collapses into a "Filters" disclosure button above the results; same controls stacked vertically inside.

**Cheatsheet modal** — a `?` icon button sits next to the navbar search input on every page. Opens a modal with a table: operator, description, example. Lists all six operators including `name:`, `description:`, and `extra:` (which is omitted from the sidebar controls as a power-user affordance). Reuses the existing `HexpmWeb.Components.Modal`.

## Data Flow

The URL (`?search=<string>&sort=<key>&page=<n>`) is the single source of truth. The LiveView stores no filter state the URL can't reconstruct. No new query parameters are introduced — the sidebar serializes *into* the existing `search` param.

Flow on a sidebar interaction:

1. User ticks `build_tool:mix` checkbox.
2. `handle_event("filter_change", params, socket)` fires.
3. Sidebar params are merged into the current `%SearchQuery{}`, then re-serialized to a string.
4. `push_patch(socket, to: ~p"/packages?search=#{new_string}")` — URL patches, no full reload.
5. `handle_params/3` parses the new `search` back into `%SearchQuery{}`, calls `Package.all/6`, assigns results.
6. The navbar search input (bound to the same assign) re-renders with the new canonical string.

Free-text edits in the navbar search box still submit via the existing form, landing on `/packages?search=...`. `handle_params` parses the submitted string; the sidebar re-renders reflecting whatever operators the user typed. Parse and serialize are symmetric, so editing either surface updates the other.

**Debouncing:** text-input filters (`depends`, `extra` values) use `phx-debounce="300"`. Checkboxes, selects, and date pickers fire immediately.

**Pagination:** any filter change resets to page 1.

**`depends:` autocomplete:** a small new query `Package.search_by_prefix/1` (`ILIKE 'prefix%'` limit 10) backs the dropdown. Triggered by `phx-change` on the input.

## Backend change

`search_param("build_tool", value, query)` in `lib/hexpm/repository/package.ex` currently ANDs repeated `build_tool:` filters (each adds another `@>` contains clause). Checkbox facets imply OR ("show me packages using mix *or* rebar3"), so the filter accepts a list and emits a single clause using the PostgreSQL array-overlap operator (`&&`) against `meta->'build_tools'`. Single-value behavior is preserved.

This is the only query-layer change. All other filters keep current semantics.

## Error handling

`SearchQuery.parse/1` returns `{:ok, query}` or `{:error, reason}`. On parse errors from user input (bad date format, malformed `extra:` value), the offending field renders with an inline error message; the valid portion of the query still runs so the user isn't left staring at an empty result set.

## Testing

**New LiveView tests** — `test/hexpm_web/live/package_live/index_test.exs`:

- Mount `/packages` with various URL params; assert results render.
- Sidebar interactions via `Phoenix.LiveViewTest`:
  - Tick `build_tool:mix` checkbox → URL patches, results narrow.
  - Enter `depends:` value → results filtered.
  - Set `updated_after:` date → results filtered.
  - Add two `extra:` rows → both applied.
  - Clear-all → URL resets.
- Assert query-preview strip matches canonical serialized string.
- Assert navbar input value stays in sync with sidebar state.

**New SearchQuery unit tests** — `test/hexpm/repository/package/search_query_test.exs`:

- `parse/1`: round-trips every filter operator; handles mixed free-text + filters; returns structured errors for malformed input.
- `serialize/1`: canonical output; stable ordering; idempotent with `parse/1`.

**Extended Package tests** — `test/hexpm/repository/package_test.exs`:

- Multiple `build_tool:` values OR together (new behavior).
- Existing single-value `build_tool:` cases still pass (regression guard).

**Component render test** for `FilterCheatsheet` — asserts every operator appears with its example.

**Browser/feature tests** — none added. LiveViewTest coverage is sufficient for filter behavior; existing Wallaby coverage of `/packages` (if any) should keep passing since URLs and form submission stay backward compatible.

**Test runner:** `make test` per project conventions.

## Backward compatibility

- All existing `/packages?search=…` URLs keep working byte-identically.
- Navbar search form still submits the same param shape.
- Public API under `/api/packages` is untouched.
- No migrations.

## Open questions

1. **Canonical list of build tools.** `build_tool:rebar3` appears in tests and `:mix`/`:rebar` appear in view helpers, but there is no central enum in the codebase. Implementation needs to locate or define the authoritative list used for the checkbox set. If no such list exists, we either (a) hardcode `["mix", "rebar3", "make"]` in the sidebar component, or (b) derive the set dynamically from the database at boot. Prefer (a) unless the user wants (b).
2. **Depends autocomplete scope.** Should the `depends:` autocomplete include packages from private repositories the current user has access to, or only public packages? Simpler and safer to scope to public packages only for v1.
