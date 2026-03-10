defmodule HexpmWeb.Dashboard.Organization.Components.PackagesTab do
  @moduledoc """
  Packages tab content for the organization dashboard.
  Lists the organization's private packages with links to their detail pages.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Buttons, only: [button_link: 1]
  import HexpmWeb.Components.Table, only: [table: 1]
  import HexpmWeb.ViewHelpers, only: [path_for_package: 1, pretty_date: 1, human_number_space: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]

  attr :organization, :map, required: true
  attr :packages, :list, required: true

  def packages_tab(assigns) do
    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:overflow-hidden">
      <div class="tw:px-6 tw:py-5 tw:border-b tw:border-grey-200 tw:flex tw:items-center tw:justify-between">
        <div>
          <h2 class="tw:text-grey-900 tw:text-lg tw:font-semibold">Packages</h2>
          <p class="tw:text-grey-500 tw:text-sm tw:mt-1">
            {package_count(@packages)} {package_label(@packages)} in this organization
          </p>
        </div>
        <.button_link
          href={"https://hex.pm/docs/private"}
          variant="outline"
          size="sm"
        >
          {icon(:heroicon, "book-open", class: "tw:w-4 tw:h-4")}
          Publishing docs
        </.button_link>
      </div>

      <%= if @packages == [] do %>
        <div class="tw:py-20 tw:flex tw:flex-col tw:items-center tw:justify-center tw:text-center tw:px-6">
          <div class="tw:w-14 tw:h-14 tw:rounded-full tw:bg-grey-100 tw:flex tw:items-center tw:justify-center tw:mb-4">
            {icon(:heroicon, "cube", class: "tw:w-7 tw:h-7 tw:text-grey-400")}
          </div>
          <h3 class="tw:text-grey-900 tw:text-base tw:font-semibold tw:mb-1">No packages yet</h3>
          <p class="tw:text-grey-500 tw:text-sm tw:max-w-sm">
            Publish your first private package to this organization using
            <code class="tw:font-mono tw:bg-grey-100 tw:px-1.5 tw:py-0.5 tw:rounded tw:text-xs">
              mix hex.publish --organization <%= @organization.name %>
            </code>
          </p>
        </div>
      <% else %>
        <div class="tw:px-6">
          <.table>
            <:header>
              <th class="tw:px-0 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
                Package
              </th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
                Version
              </th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
                Downloads
              </th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
                Updated
              </th>
            </:header>
            <:row :for={package <- @packages}>
              <.package_row package={package} />
            </:row>
          </.table>
        </div>
      <% end %>
    </div>
    """
  end

  attr :package, :map, required: true

  defp package_row(assigns) do
    ~H"""
    <tr
      class="tw:hover:bg-grey-50 tw:cursor-pointer tw:transition-colors"
      onclick={"window.location='#{path_for_package(@package)}'"}
    >
      <td class="tw:px-0 tw:py-4">
        <div class="tw:flex tw:items-center tw:gap-2">
          <span class="tw:text-sm tw:font-medium tw:text-grey-900">{@package.name}</span>
          <%= if @package.meta && @package.meta.description do %>
            <span class="tw:text-xs tw:text-grey-400 tw:truncate tw:max-w-xs tw:hidden tw:lg:block">
              — {@package.meta.description}
            </span>
          <% end %>
        </div>
      </td>
      <td class="tw:px-4 tw:py-4">
        <span class="tw:text-sm tw:text-grey-600 tw:font-mono">
          <%= if @package.latest_release do %>
            v{@package.latest_release.version}
          <% else %>
            —
          <% end %>
        </span>
      </td>
      <td class="tw:px-4 tw:py-4">
        <span class="tw:text-sm tw:text-grey-600">
          {human_number_space(package_downloads(@package))}
        </span>
      </td>
      <td class="tw:px-4 tw:py-4">
        <span class="tw:text-sm tw:text-grey-500">
          {pretty_date(@package.updated_at)}
        </span>
      </td>
    </tr>
    """
  end

  defp package_count(packages), do: length(packages)

  defp package_label(packages) do
    if package_count(packages) == 1, do: "package", else: "packages"
  end

  defp package_downloads(%{downloads: downloads}) when is_list(downloads) do
    Enum.reduce(downloads, 0, fn d, acc -> acc + (d.downloads || 0) end)
  end

  defp package_downloads(_), do: 0
end
