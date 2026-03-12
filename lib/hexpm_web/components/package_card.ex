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
      class="bg-white border border-grey-200 rounded-lg p-4 flex flex-col hover:border-grey-300 transition-colors"
    >
      <div class="flex items-baseline gap-2 mb-2">
        <h3 class="text-grey-900 text-lg font-medium">
          {package_name(@package)}
        </h3>
        <span class="text-grey-500 text-xs">
          {@package.latest_release.version}
        </span>
        <div class="ml-auto flex items-center gap-1 text-grey-400 text-sm">
          {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-down-tray", class: "w-3.5 h-3.5")}
          <span>{human_number_space(@downloads)}+</span>
        </div>
      </div>

      <p class="text-grey-500 text-sm mb-auto line-clamp-1">
        {@package.meta.description || "No description available"}
      </p>

      <%= if @updated_at do %>
        <div class="text-xs text-grey-400 mt-2">
          Last Updated:
          <span class="font-semibold text-grey-600">
            {human_relative_time_from_now(@updated_at)}
          </span>
        </div>
      <% end %>
    </a>
    """
  end
end
