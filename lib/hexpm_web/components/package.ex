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
    <div class="tw:mb-6 tw:bg-grey-50 tw:rounded-xl tw:p-4 tw:lg:p-6">
      <%!-- Desktop: All letters visible --%>
      <div class="tw:hidden tw:sm:block">
        <h3 class="tw:text-grey-700 tw:text-sm tw:font-semibold tw:mb-3 tw:uppercase tw:tracking-wide">
          Browse by Letter
        </h3>
        <div class="tw:flex tw:flex-wrap tw:gap-2">
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
            class="tw:inline-flex tw:items-center tw:justify-center tw:px-3 tw:h-10 tw:bg-grey-200 tw:text-grey-700 tw:text-sm tw:font-medium tw:rounded-lg tw:border tw:border-grey-300 hover:tw:bg-grey-300 tw:transition-all"
          >
            Clear
          </a>
        </div>
      </div>
      <%!-- Mobile: Compact grid --%>
      <div class="tw:sm:hidden">
        <div class="tw:flex tw:items-center tw:justify-between tw:mb-3">
          <h3 class="tw:text-grey-700 tw:text-sm tw:font-semibold tw:uppercase tw:tracking-wide">
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
            class="tw:text-primary-600 tw:text-sm tw:font-medium hover:tw:text-primary-700 tw:transition-colors"
          >
            <span id="letter-toggle-show">Show All</span>
            <span id="letter-toggle-hide" class="tw:hidden">Hide</span>
          </button>
        </div>
        <%!-- Single grid that shows/hides letters --%>
        <div class="tw:grid tw:grid-cols-7 tw:gap-2">
          <a
            :for={{letter, index} <- Enum.with_index(@letters)}
            href={~p"/packages?letter=#{letter}"}
            data-mobile-letter-extra={index >= 13 || nil}
            style={index >= 13 && "display: none;"}
            class={letter_button_classes(@current_letter, letter, :mobile)}
          >
            {letter}
          </a>
          <a
            :if={@current_letter}
            href={~p"/packages"}
            data-mobile-letter-extra
            style="display: none;"
            class="tw:col-span-2 tw:inline-flex tw:items-center tw:justify-center tw:h-10 tw:bg-grey-200 tw:text-grey-700 tw:text-sm tw:font-medium tw:rounded-lg tw:border tw:border-grey-300 hover:tw:bg-grey-300 tw:transition-all"
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
      <div class="tw:hidden tw:lg:block tw:bg-grey-50 tw:rounded-lg tw:p-4">
        <h3 class="tw:text-grey-700 tw:text-sm tw:font-semibold tw:mb-3">Sort by</h3>
        <div class="tw:flex tw:flex-wrap tw:gap-2">
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
      <div class="tw:lg:hidden">
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
        :desktop -> "tw:size-9.5"
        :mobile -> "tw:size-10"
      end

    [
      "tw:inline-flex tw:items-center tw:justify-center #{size_class} tw:font-medium tw:rounded-lg tw:border tw:transition-all",
      if(current_letter == letter,
        do: "tw:bg-primary-600 tw:text-white tw:border-primary-600 tw:shadow-sm",
        else:
          "tw:bg-white tw:text-grey-700 tw:border-grey-200 hover:tw:bg-primary-50 hover:tw:text-primary-700 hover:tw:border-primary-300"
      )
    ]
  end

  defp sort_button_classes(current_sort, value) do
    [
      "tw:inline-flex tw:items-center tw:px-3 tw:py-1.5 tw:rounded-md tw:text-sm tw:font-medium tw:transition-colors",
      if(current_sort == value,
        do: "tw:bg-primary-600 tw:text-white tw:shadow-sm",
        else: "tw:bg-white tw:text-grey-700 hover:tw:bg-grey-100"
      )
    ]
  end
end
