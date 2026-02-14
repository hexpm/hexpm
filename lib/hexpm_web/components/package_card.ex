defmodule HexpmWeb.Components.PackageCard do
  @moduledoc """
  Package card component for displaying package information in grid layouts.
  """
  use Phoenix.Component
  import HexpmWeb.ViewHelpers

  @doc """
  Renders a package card with name, version, downloads, and description.
  """
  attr :package, :map, required: true
  attr :downloads, :integer, required: true
  attr :updated_at, :any, default: nil

  def package_card(assigns) do
    ~H"""
    <a
      href={path_for_package(@package)}
      class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-4 tw:flex tw:flex-col tw:hover:border-grey-300 tw:transition-colors"
    >
      <div class="tw:flex tw:items-baseline tw:gap-2 tw:mb-2">
        <h3 class="tw:text-grey-900 tw:text-lg tw:font-medium">
          {package_name(@package)}
        </h3>
        <span class="tw:text-grey-500 tw:text-xs">
          {@package.latest_release.version}
        </span>
        <div class="tw:ml-auto tw:flex tw:items-center tw:gap-1 tw:text-grey-400 tw:text-sm">
          {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-down-tray", class: "tw:w-3.5 tw:h-3.5")}
          <span>{human_number_space(@downloads)}+</span>
        </div>
      </div>

      <p class="tw:text-grey-500 tw:text-sm tw:mb-auto tw:line-clamp-1">
        {@package.meta.description || "No description available"}
      </p>

      <%= if @updated_at do %>
        <div class="tw:text-xs tw:text-grey-400 tw:mt-2">
          Last Updated:
          <span class="tw:font-semibold tw:text-grey-600">
            {human_relative_time_from_now(@updated_at)}
          </span>
        </div>
      <% end %>
    </a>
    """
  end
end
