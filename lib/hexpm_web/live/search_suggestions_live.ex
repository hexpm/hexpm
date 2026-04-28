defmodule HexpmWeb.SearchSuggestionsLive do
  @moduledoc """
  LiveView component for searching packages.
  Uses the `Hexpm.Repository.Packages.suggest/3` function to get suggestions
  based on a trigram search of the package name and description with weighted ranking.

  Defaults to 8 suggestions using `default_limit`.

  Session keys:
    - `"variant"` - `"home"` | `"home-mobile"` | `"nav"` (default: `"home"`)
    - `"limit"` - integer max results (default: 8)
    - `"autofocus"` - boolean, focuses the input on mount (nav variant only)
    - `"search"` - pre-filled search term (nav variant only)
  """
  use HexpmWeb, :live_view

  alias Hexpm.Repository.{Packages, Repository}
  import HexpmWeb.SearchSuggestionsComponent

  @default_limit 8

  def mount(_params, session, socket) do
    variant = Map.get(session, "variant", "home")
    limit = Map.get(session, "limit", @default_limit)
    autofocus = Map.get(session, "autofocus", false)
    term = Map.get(session, "search") || ""

    {:ok,
     socket
     |> assign(:variant, variant)
     |> assign(:limit, limit)
     |> assign(:autofocus, autofocus)
     |> assign(:term, term)
     |> assign(:items, [])
     |> assign(:open, false)
     |> assign(:active, nil), layout: false}
  end

  def handle_event("suggest", params, socket) do
    term = extract_search_term(params)
    repository = Repository.hexpm()

    items =
      if String.trim(term) == "",
        do: [],
        else: Packages.suggest(repository, term, socket.assigns.limit)

    {:noreply,
     socket
     |> assign(:term, term)
     |> assign(:items, items)
     |> assign(:open, items != [])
     |> assign(:active, nil)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(:open, false) |> assign(:active, nil)}
  end

  def handle_event("submit", %{"search" => term}, socket) do
    case socket.assigns.active && Enum.at(socket.assigns.items, socket.assigns.active) do
      nil ->
        to = ~p"/packages?#{[search: term, sort: "recent_downloads"]}"
        {:noreply, push_navigate(socket, to: to)}

      item ->
        {:noreply, push_navigate(socket, to: item.href)}
    end
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, socket |> assign(:open, false) |> assign(:active, nil)}
  end

  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    count = length(socket.assigns.items)

    if count == 0 do
      {:noreply, socket}
    else
      new_active =
        case socket.assigns.active do
          nil -> 0
          i when i + 1 >= count -> 0
          i -> i + 1
        end

      {:noreply, assign(socket, :active, new_active)}
    end
  end

  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    count = length(socket.assigns.items)

    if count == 0 do
      {:noreply, socket}
    else
      new_active =
        case socket.assigns.active do
          nil -> count - 1
          0 -> count - 1
          i -> i - 1
        end

      {:noreply, assign(socket, :active, new_active)}
    end
  end

  def handle_event("keydown", %{"key" => _key}, socket) do
    {:noreply, socket}
  end

  def render(%{variant: "nav"} = assigns) do
    ~H"""
    <form
      method="get"
      action={~p"/packages"}
      role="search"
      class="min-w-0 flex-1"
      phx-submit="submit"
      autocomplete="off"
    >
      <div class="relative flex items-center" phx-click-away="close">
        <input
          type="search"
          placeholder="Find packages..."
          name="search"
          id={input_id(@variant)}
          value={@term}
          autocomplete="off"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={if @open, do: "true", else: "false"}
          aria-controls={listbox_id(@variant)}
          aria-activedescendant={active_id(@variant, @active)}
          phx-change="suggest"
          phx-keydown="keydown"
          phx-debounce="100"
          phx-hook="SearchShortcut"
          autofocus={@autofocus}
          class="w-full h-[40px] bg-grey-800 border border-grey-600 rounded-lg px-3 pl-10 py-[11px] text-white leading-4 placeholder:text-grey-300 focus:outline-none focus:border-grey-500 focus:shadow-[inset_0px_0px_6px_0px_rgba(255,255,255,0.3)]"
        />
        <input type="hidden" name="sort" value="recent_downloads" />
        <label class="sr-only" for={input_id(@variant)}>Find packages</label>

        <%= if @open and @items != [] do %>
          <.suggestions variant={@variant} items={@items} active={@active} />
        <% end %>
      </div>
    </form>
    """
  end

  def render(assigns) do
    ~H"""
    <form
      method="get"
      action={~p"/packages"}
      role="search"
      phx-submit="submit"
      autocomplete="off"
    >
      <div class="relative" phx-click-away="close">
        <input
          type="search"
          placeholder="Find packages..."
          name="search"
          id={input_id(@variant)}
          value={@term}
          autocomplete="off"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={if @open, do: "true", else: "false"}
          aria-controls={listbox_id(@variant)}
          aria-activedescendant={active_id(@variant, @active)}
          phx-change="suggest"
          phx-keydown="keydown"
          phx-debounce="100"
          phx-hook="SearchShortcut"
          class="w-full border border-grey-200 dark:border-grey-600 rounded-lg px-4 py-3 text-grey-800 dark:text-white dark:bg-grey-700 placeholder:text-grey-400 dark:placeholder:text-grey-400 focus:outline-none focus:border-primary-400"
        />
        <input type="hidden" name="sort" value="recent_downloads" />
        <label class="sr-only" for={input_id(@variant)}>Find packages</label>

        <button
          type="submit"
          class="absolute right-3 top-1/2 -translate-y-1/2 text-grey-400 hover:text-grey-600 dark:hover:text-grey-200"
        >
          <span class="sr-only">Search</span>
        </button>

        <%= if @open and @items != [] do %>
          <.suggestions variant={@variant} items={@items} active={@active} />
        <% end %>
      </div>
    </form>
    """
  end

  defp extract_search_term(params) do
    term = params["search"] || params["value"] || ""
    String.slice(to_string(term), 0, 100)
  end

  defp input_id("home"), do: "home-search-input"
  defp input_id("home-mobile"), do: "home-mobile-search-input"
  defp input_id("nav"), do: "nav-search-input"
  defp input_id(_), do: "home-search-input"

  defp active_id(_variant, nil), do: nil
  defp active_id(variant, idx), do: option_id(variant, idx)
end
