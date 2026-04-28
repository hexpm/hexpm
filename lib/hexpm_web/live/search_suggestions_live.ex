defmodule HexpmWeb.SearchSuggestionsLive do
  @moduledoc """
  LiveView component for searching packages.
  Uses the `Hexpm.Repository.Packages.suggest/3` function to get suggestions
  based on a trigram search of the package name and description with weighted ranking.

  Defaults to 8 suggestions using `default_limit`.
  """
  use HexpmWeb, :live_view

  alias Hexpm.Repository.{Packages, Repository}
  import HexpmWeb.SearchSuggestionsComponent

  @default_limit 8

  def mount(_params, session, socket) do
    variant = Map.get(session, "variant", "home")
    limit = Map.get(session, "limit", @default_limit)

    {:ok,
     socket
     |> assign(:variant, variant)
     |> assign(:limit, limit)
     |> assign(:term, "")
     |> assign(:items, [])
     |> assign(:open, false)
     |> assign(:active, 0)}
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
     |> assign(:active, 0)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(:open, false) |> assign(:active, 0)}
  end

  def handle_event("submit", %{"search" => term}, socket) do
    items = socket.assigns.items

    active =
      if socket.assigns.active >= 0 and socket.assigns.active < length(items) do
        socket.assigns.active
      else
        0
      end

    case Enum.at(items, active) do
      nil ->
        to = ~p"/packages?#{[search: term, sort: "recent_downloads"]}"
        {:noreply, push_navigate(socket, to: to)}

      item ->
        {:noreply, push_navigate(socket, to: item.href)}
    end
  end

  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    active = socket.assigns.active
    count = length(socket.assigns.items)

    new_active =
      case active do
        i when i + 1 >= count -> 0
        i -> i + 1
      end

    {:noreply, assign(socket, :active, new_active)}
  end

  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    active = socket.assigns.active
    count = length(socket.assigns.items)

    new_active =
      case active do
        0 -> count - 1
        i -> i - 1
      end

    {:noreply, assign(socket, :active, new_active)}
  end

  def handle_event("keydown", %{"key" => _key}, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.form
      for={%{}}
      method="get"
      action={~p"/packages"}
      role="search"
      class={form_class(@variant)}
      phx-change="suggest"
      phx-submit="submit"
      autocomplete="off"
    >
      <div
        class="input-group dropdown"
        phx-click-away="close"
        phx-window-keydown="keydown"
        style="position: relative;"
      >
        <input
          type="search"
          class="form-control"
          placeholder="Find packages"
          name="search"
          id={input_id(@variant)}
          value={@term}
          tabindex="1"
          autocomplete="off"
          autocapitalize="off"
          autocorrect="off"
          spellcheck="false"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={if @open, do: "true", else: "false"}
          aria-controls={listbox_id(@variant)}
          aria-activedescendant={active_id(@variant, @active)}
          phx-input="suggest"
          phx-debounce="100"
        />
        <input type="hidden" name="sort" value="recent_downloads" />
        <label class="sr-only" for={input_id(@variant)}>Find packages</label>
        <span class="input-group-btn">
          <button type="submit" class="btn btn-search" tabindex="1">
            {icon(:heroicon, "magnifying-glass", width: 18, height: 18)}
            <span class="sr-only">Search</span>
          </button>
        </span>

        <%= if @open and @items != [] do %>
          <.suggestions variant={@variant} items={@items} active={@active} />
        <% end %>
      </div>
    </.form>
    """
  end

  defp extract_search_term(params) do
    term = params["search"] || params["value"] || ""
    String.slice(to_string(term), 0, 100)
  end

  defp form_class("nav"), do: "navbar-form pull-left-non-mobile"
  defp form_class(_), do: nil

  defp input_id("home"), do: "search"
  defp input_id("nav"), do: "navbar-search"
  defp input_id(_), do: "search"

  defp active_id(_variant, nil), do: nil
  defp active_id(variant, idx), do: option_id(variant, idx)
end
