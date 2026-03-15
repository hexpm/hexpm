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
    <div class="bg-white border border-grey-200 rounded-lg overflow-hidden">
      <div class="px-6 py-5 border-b border-grey-200 flex items-center justify-between">
        <div>
          <h2 class="text-grey-900 text-lg font-semibold">Packages</h2>
          <p class="text-grey-500 text-sm mt-1">
            {package_count(@packages)} {package_label(@packages)} in this organization
          </p>
        </div>
        <.button_link
          href={~p"/docs/private"}
          variant="outline"
          size="sm"
        >
          {icon(:heroicon, "book-open", class: "w-4 h-4")} Publishing docs
        </.button_link>
      </div>

      <%= if @packages == [] do %>
        <div class="py-20 flex flex-col items-center justify-center text-center px-6">
          <div class="w-14 h-14 rounded-full bg-grey-100 flex items-center justify-center mb-4">
            {icon(:heroicon, "cube", class: "w-7 h-7 text-grey-400")}
          </div>
          <h3 class="text-grey-900 text-base font-semibold mb-1">No packages yet</h3>
          <p class="text-grey-500 text-sm max-w-sm">
            Publish your first private package to this organization using
            <code class="font-mono bg-grey-100 px-1.5 py-0.5 rounded text-xs">
              mix hex.publish --organization {@organization.name}
            </code>
          </p>
        </div>
      <% else %>
        <div class="px-6">
          <.table>
            <:header>
              <th class="px-0 py-3 text-left text-sm font-medium text-grey-500">
                Package
              </th>
              <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">
                Version
              </th>
              <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">
                Downloads
              </th>
              <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">
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
      class="hover:bg-grey-50 cursor-pointer transition-colors"
      onclick={"window.location='#{path_for_package(@package)}'"}
    >
      <td class="px-0 py-4">
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium text-grey-900">{@package.name}</span>
          <%= if @package.meta && @package.meta.description do %>
            <span class="text-xs text-grey-400 truncate max-w-xs hidden lg:block">
              — {@package.meta.description}
            </span>
          <% end %>
        </div>
      </td>
      <td class="px-4 py-4">
        <span class="text-sm text-grey-600 font-mono">
          <%= if @package.latest_release do %>
            v{@package.latest_release.version}
          <% else %>
            —
          <% end %>
        </span>
      </td>
      <td class="px-4 py-4">
        <span class="text-sm text-grey-600">
          {human_number_space(package_downloads(@package))}
        </span>
      </td>
      <td class="px-4 py-4">
        <span class="text-sm text-grey-500">
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
