defmodule HexpmWeb.Components.Package do
  @moduledoc """
  Reusable components for package pages.
  """
  use Phoenix.Component
  import HexpmWeb.Components.Input, only: [select_input: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  alias Phoenix.LiveView.JS

  @doc """
  Renders a letter browser for filtering packages alphabetically.
  On mobile, it shows a compact grid. On desktop, it shows all letters inline.

  ## Examples

      <.letter_browser letters={@letters} current_letter={@letter} />
  """
  attr :current_letter, :string, default: nil
  attr :letters, :list, required: true

  def letter_browser(assigns) do
    ~H"""
    <div class="mb-6 bg-grey-50 rounded-xl p-4 lg:p-6">
      <%!-- Desktop: All letters visible --%>
      <div class="hidden sm:block">
        <h3 class="text-grey-700 text-sm font-semibold mb-3 uppercase tracking-wide">
          Browse by Letter
        </h3>
        <div class="flex flex-wrap gap-2">
          <a
            :for={letter <- @letters}
            href={~p"/packages?letter=#{letter}"}
            class={letter_button_classes(@current_letter, letter, :desktop)}
          >
            {letter}
          </a>
          <a
            :if={@current_letter}
            href={~p"/packages"}
            class="inline-flex items-center justify-center px-3 h-10 bg-grey-200 text-grey-700 text-sm font-medium rounded-lg border border-grey-300 hover:bg-grey-300 transition-all"
          >
            Clear
          </a>
        </div>
      </div>
      <%!-- Mobile: Compact grid --%>
      <div class="sm:hidden">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-grey-700 text-sm font-semibold uppercase tracking-wide">
            <span :if={@current_letter}>Letter: {@current_letter}</span>
            <span :if={!@current_letter}>Browse by Letter</span>
          </h3>
          <button
            type="button"
            phx-click={
              JS.toggle(
                to: "[data-mobile-letter-extra]",
                in: {"ease-out duration-100", "opacity-0", "opacity-100"},
                out: {"ease-in duration-100", "opacity-100", "opacity-0"},
                display: "inline-flex"
              )
              |> JS.toggle(to: "#letter-toggle-show")
              |> JS.toggle(to: "#letter-toggle-hide")
            }
            class="text-primary-600 text-sm font-medium hover:text-primary-700 transition-colors"
          >
            <span id="letter-toggle-show">Show All</span>
            <span id="letter-toggle-hide" class="hidden">Hide</span>
          </button>
        </div>
        <%!-- Single grid that shows/hides letters --%>
        <div class="grid grid-cols-7 gap-2">
          <a
            :for={{letter, index} <- Enum.with_index(@letters)}
            href={~p"/packages?letter=#{letter}"}
            data-mobile-letter-extra={index >= 13 || nil}
            class={[index >= 13 && "hidden" | letter_button_classes(@current_letter, letter, :mobile)]}
          >
            {letter}
          </a>
          <a
            :if={@current_letter}
            href={~p"/packages"}
            data-mobile-letter-extra
            class="hidden col-span-2 inline-flex items-center justify-center h-10 bg-grey-200 text-grey-700 text-sm font-medium rounded-lg border border-grey-300 hover:bg-grey-300 transition-all"
          >
            Clear
          </a>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a sort dropdown for package lists.
  On mobile, shows as a select dropdown. On desktop, shows as pill buttons.

  ## Examples

      <.sort_selector
        sort={@sort}
        search={@search}
        page={@page}
      />
  """
  attr :page, :any, default: nil
  attr :search, :string, default: nil
  attr :sort, :atom, required: true

  def sort_selector(assigns) do
    assigns =
      assign(assigns, :sort_options, [
        {:name, "Name"},
        {:total_downloads, "Total downloads"},
        {:recent_downloads, "Recent downloads"},
        {:inserted_at, "Recently created"},
        {:updated_at, "Recently updated"}
      ])

    ~H"""
    <div>
      <%!-- Desktop: Pill buttons --%>
      <div class="hidden lg:block bg-grey-50 rounded-lg p-4">
        <h3 class="text-grey-700 text-sm font-semibold mb-3">Sort by</h3>
        <div class="flex flex-wrap gap-2">
          <a
            :for={{value, label} <- @sort_options}
            href={
              ~p"/packages?#{HexpmWeb.ViewHelpers.params(search: @search, page: @page, sort: to_string(value))}"
            }
            class={sort_button_classes(@sort, value)}
          >
            {label}
          </a>
        </div>
      </div>
      <%!-- Mobile: Native select dropdown --%>
      <div class="lg:hidden">
        <% # Build options as {label, url} tuples for the select
        select_options =
          Enum.map(@sort_options, fn {value, label} ->
            params =
              HexpmWeb.ViewHelpers.params(search: @search, page: @page, sort: to_string(value))

            url = ~p"/packages?#{params}"
            {label, url}
          end)

        # Find current selection URL
        current_params =
          HexpmWeb.ViewHelpers.params(search: @search, page: @page, sort: to_string(@sort))

        current_value = ~p"/packages?#{current_params}" %>
        <.select_input
          id="sort-select"
          name="sort"
          label="Sort by"
          options={select_options}
          value={current_value}
          onchange="window.location.href = this.value"
        />
      </div>
    </div>
    """
  end

  defp letter_button_classes(current_letter, letter, variant) do
    size_class =
      case variant do
        :desktop -> "size-9.5"
        :mobile -> "size-10"
      end

    [
      "inline-flex items-center justify-center #{size_class} font-medium rounded-lg border transition-all",
      if(current_letter == letter,
        do: "bg-primary-600 text-white border-primary-600 shadow-sm",
        else:
          "bg-white text-grey-700 border-grey-200 hover:bg-primary-50 hover:text-primary-700 hover:border-primary-300"
      )
    ]
  end

  defp sort_button_classes(current_sort, value) do
    [
      "inline-flex items-center px-3 py-1.5 rounded-md text-sm font-medium transition-colors",
      if(current_sort == value,
        do: "bg-primary-600 text-white shadow-sm",
        else: "bg-white text-grey-700 hover:bg-grey-100"
      )
    ]
  end
end
