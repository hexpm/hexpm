defmodule HexpmWeb.SearchSuggestionsComponent do
  use Phoenix.Component

  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]

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

  attr :active, :any,
    default: nil,
    doc: "Index of the currently active item (nil means no keyboard selection)"

  def suggestions(%{variant: "nav"} = assigns) do
    ~H"""
    <div class="absolute inset-x-0 top-full z-50 w-full mt-1 rounded-lg shadow-xl bg-grey-700 border border-grey-600 overflow-hidden">
      <ul id={listbox_id(@variant)} class="py-1" role="listbox">
        <%= if @items == [] do %>
          <li role="option" aria-disabled="true" class="px-3 py-3 text-sm text-grey-300">
            No suggestions found
          </li>
        <% end %>
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <li
            role="option"
            id={option_id(@variant, idx)}
            aria-selected={if @active == idx, do: "true", else: "false"}
          >
            <a
              href={item.href}
              class={[
                "flex flex-col px-3 py-2 text-sm no-underline",
                if(@active == idx, do: "bg-grey-600", else: "hover:bg-grey-600")
              ]}
            >
              <span class="font-medium text-white">
                {item.name_html}
                <%= if item.latest_version do %>
                  <span class="text-xs text-grey-300 ml-1.5 font-normal">
                    v{item.latest_version}
                  </span>
                <% end %>
              </span>
              <%= if item.description_html do %>
                <span class="text-xs text-grey-300 truncate mt-0.5">
                  {item.description_html}
                </span>
              <% end %>
              <%= if is_integer(item.recent_downloads) do %>
                <span class="text-xs text-grey-400 mt-0.5">
                  {ViewHelpers.human_number_space(item.recent_downloads)} downloads (recent)
                </span>
              <% end %>
            </a>
          </li>
        <% end %>
      </ul>
      <.syntax_help_footer variant={@variant} />
    </div>
    """
  end

  def suggestions(assigns) do
    ~H"""
    <div class="absolute inset-x-0 top-full z-50 w-full mt-1 rounded-lg shadow-xl bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 overflow-hidden">
      <ul id={listbox_id(@variant)} class="py-1" role="listbox">
        <%= if @items == [] do %>
          <li
            role="option"
            aria-disabled="true"
            class="px-3 py-3 text-sm text-grey-500 dark:text-grey-300"
          >
            No suggestions found
          </li>
        <% end %>
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <li
            role="option"
            id={option_id(@variant, idx)}
            aria-selected={if @active == idx, do: "true", else: "false"}
          >
            <a
              href={item.href}
              class={[
                "flex flex-col px-3 py-2 text-sm no-underline",
                if(@active == idx,
                  do: "bg-primary-50 dark:bg-grey-600",
                  else: "hover:bg-grey-50 dark:hover:bg-grey-600"
                )
              ]}
            >
              <span class="font-medium text-grey-900 dark:text-white">
                {item.name_html}
                <%= if item.latest_version do %>
                  <span class="text-xs text-grey-400 dark:text-grey-300 ml-1.5 font-normal">
                    v{item.latest_version}
                  </span>
                <% end %>
              </span>
              <%= if item.description_html do %>
                <span class="text-xs text-grey-500 dark:text-grey-300 truncate mt-0.5">
                  {item.description_html}
                </span>
              <% end %>
              <%= if is_integer(item.recent_downloads) do %>
                <span class="text-xs text-grey-400 mt-0.5">
                  {ViewHelpers.human_number_space(item.recent_downloads)} downloads (recent)
                </span>
              <% end %>
            </a>
          </li>
        <% end %>
      </ul>
      <.syntax_help_footer variant={@variant} />
    </div>
    """
  end

  attr :variant, :string, required: true

  defp syntax_help_footer(%{variant: "nav"} = assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 border-t border-grey-600 bg-grey-800/70 px-4 py-3 text-xs text-grey-300">
      <.syntax_examples class="hidden sm:flex" code_class="bg-grey-700 text-grey-100 border-grey-600" />
      <.syntax_help_button class="text-primary-300 hover:text-white" />
    </div>
    """
  end

  defp syntax_help_footer(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 border-t border-grey-200 bg-grey-50 px-4 py-3 text-xs text-grey-500 dark:border-grey-600 dark:bg-grey-800/70 dark:text-grey-300">
      <.syntax_examples
        class="hidden sm:flex"
        code_class="bg-white text-grey-700 border-grey-200 dark:bg-grey-700 dark:text-grey-100 dark:border-grey-600"
      />
      <.syntax_help_button class="text-primary-600 hover:text-primary-700 dark:text-primary-300 dark:hover:text-white" />
    </div>
    """
  end

  attr :class, :string, default: ""
  attr :code_class, :string, required: true

  defp syntax_examples(assigns) do
    ~H"""
    <div class={["min-w-0 flex-wrap items-center gap-x-5 gap-y-2", @class]}>
      <span class="inline-flex items-center gap-1.5 whitespace-nowrap">
        Wildcard <code class={["rounded border px-1 py-0.5 font-mono", @code_class]}>name:phx*</code>
      </span>
    </div>
    """
  end

  attr :class, :string, default: ""

  defp syntax_help_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={show_modal("search-cheatsheet")}
      class={["ml-auto inline-flex shrink-0 items-center gap-1 font-medium cursor-pointer", @class]}
    >
      Syntax Help {icon(:heroicon, "question-mark-circle", width: 14, height: 14)}
    </button>
    """
  end

  def listbox_id("home"), do: "home-suggest-list"
  def listbox_id("home-mobile"), do: "home-mobile-suggest-list"
  def listbox_id("nav"), do: "nav-suggest-list"
  def listbox_id(_), do: "home-suggest-list"

  def option_id(variant, idx), do: "#{listbox_id(variant)}-opt-#{idx}"
end
