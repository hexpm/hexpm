defmodule HexpmWeb.SearchSuggestionsLive do
  use HexpmWeb, :live_view

  alias Hexpm.Repository.{Packages, Repository}

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
     |> assign(:active, nil)}
  end

  def handle_event("suggest", params, socket) do
    term = params["search"] || params["value"] || ""
    term = String.slice(to_string(term), 0, 100)
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
     |> assign(:active, if(items == [], do: nil, else: 0))}
  end

  # (Escape key behavior removed per rollback request)

  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(:open, false) |> assign(:active, nil)}
  end

  def handle_event("submit", %{"search" => term}, socket) do
    items = socket.assigns.items
    active = socket.assigns.active

    cond do
      is_list(items) and not is_nil(active) and active >= 0 and active < length(items) ->
        item = Enum.at(items, active)
        {:noreply, push_navigate(socket, to: item.href)}

      true ->
        to = ~p"/packages?#{[search: term, sort: "recent_downloads"]}"
        {:noreply, push_navigate(socket, to: to)}
    end
  end

  # Keyboard navigation (ArrowUp/ArrowDown) to move active selection
  def handle_event("keydown", params, socket) do
    key = params["key"] || get_in(params, ["value", "key"]) || ""
    items = socket.assigns.items
    active = socket.assigns.active

    case key do
      "ArrowDown" ->
        new_active =
          cond do
            items == [] -> nil
            is_nil(active) -> 0
            true -> min(active + 1, length(items) - 1)
          end

        {:noreply, assign(socket, :active, new_active)}

      "ArrowUp" ->
        new_active =
          cond do
            items == [] -> nil
            is_nil(active) -> 0
            true -> max(active - 1, 0)
          end

        {:noreply, assign(socket, :active, new_active)}

      _ ->
        {:noreply, socket}
    end
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
          phx-keydown="keydown"
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
          <ul
            id={listbox_id(@variant)}
            class="dropdown-menu search-suggestions"
            role="listbox"
            style="display: block; position: absolute; left: 0; right: 0; top: 100%; min-width: 100%; width: 100%; z-index: 1000; border-radius: 8px; box-sizing: border-box; border: 10px solid rgba(0,0,0,.1); margin: 2px 0 0 0; padding: 6px 0;"
          >
            <%= for {item, idx} <- Enum.with_index(@items) do %>
              <li role="option" id={option_id(@variant, idx)} aria-selected={@active == idx}>
                <a
                  href={item.href}
                  class={if @active == idx, do: "active", else: nil}
                  style={if @active == idx, do: "background-color: #e9ddff;", else: nil}
                >
                  {raw(item.name_html)}
                  <%= if item.latest_version do %>
                    <span class="text-muted" style="font-size: 12px; margin-left: 6px;">
                      v{item.latest_version}
                    </span>
                  <% end %>
                  <%= if item.description_html do %>
                    <div class="text-muted" style="font-size: 12px;">
                      {raw(item.description_html)}
                    </div>
                  <% end %>
                  <%= if is_integer(item.recent_downloads) do %>
                    <div class="text-muted" style="font-size: 12px;">
                      {ViewHelpers.human_number_space(item.recent_downloads)} downloads (recent)
                    </div>
                  <% end %>
                </a>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>
    </.form>
    """
  end

  defp form_class("nav"), do: "navbar-form pull-left-non-mobile"
  defp form_class(_), do: nil

  defp input_id("home"), do: "search"
  defp input_id("nav"), do: "navbar-search"
  defp input_id(_), do: "search"

  defp listbox_id("home"), do: "home-suggest-list"
  defp listbox_id("nav"), do: "nav-suggest-list"
  defp listbox_id(_), do: "home-suggest-list"

  defp option_id(variant, idx), do: "#{listbox_id(variant)}-opt-#{idx}"
  defp active_id(_variant, nil), do: nil
  defp active_id(variant, idx), do: option_id(variant, idx)
end
