defmodule HexpmWeb.SearchSuggestionsComponent do
  use Phoenix.Component

  import Phoenix.HTML

  alias HexpmWeb.ViewHelpers

  @doc """
  Renders a dropdown list of search suggestions.

  ## Attributes

  * `:variant` (required) - The variant of the search input. Can be `"home"` or `"nav"`.
    Used to generate unique IDs for accessibility.

  * `:items` (required) - A list of suggestion items to display. Each item should be a map with:
    * `:href` - The URL to navigate to when the item is clicked
    * `:name_html` - The HTML content for the item name
    * `:latest_version` (optional) - The latest version string to display
    * `:description_html` (optional) - HTML content for the item description
    * `:recent_downloads` (optional) - Integer representing recent download count

  * `:active` - The index of the currently active/selected item. Can be `nil` or an integer.
    The active item will be highlighted with a different background color.

  ## Examples

      <.suggestions
        variant="home"
        items={[
          %{href: "/packages/plug", name_html: "Plug", latest_version: "1.15.0"},
          %{href: "/packages/phoenix", name_html: "Phoenix", latest_version: "1.7.0"}
        ]}
        active={0}
      />
  """
  attr :variant, :string,
    required: true,
    doc: "The variant of the search input (\"home\" or \"nav\")"

  attr :items, :list, required: true, doc: "List of suggestion items to display"
  attr :active, :integer, default: nil, doc: "Index of the currently active item"

  def suggestions(assigns) do
    ~H"""
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
    """
  end

  def listbox_id("home"), do: "home-suggest-list"
  def listbox_id("nav"), do: "nav-suggest-list"
  def listbox_id(_), do: "home-suggest-list"

  def option_id(variant, idx), do: "#{listbox_id(variant)}-opt-#{idx}"
end
