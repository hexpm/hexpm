defmodule HexpmWeb.Dashboard.Key.Components.KeyManagementCard do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Badge
  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.Components.Table
  import HexpmWeb.Components.Tooltip
  import HexpmWeb.ViewHelpers, only: [pretty_date: 1, pretty_datetime: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]
  import HexpmWeb.Dashboard.Key.Components.RevokeKeyModal
  import HexpmWeb.Dashboard.Key.Components.GenerateKeyModal
  import HexpmWeb.Dashboard.Key.Components.KeyGeneratedModal

  alias Hexpm.Accounts.KeyPermission

  attr :keys, :list, required: true
  attr :organizations, :list, required: true
  attr :packages, :list, required: true
  attr :key_changeset, :map, required: true
  attr :csrf_token, :string, required: true
  attr :create_key_path, :string, required: true
  attr :delete_key_path, :string, required: true
  attr :generated_key, :map, default: nil

  def key_management_card(assigns) do
    assigns = assign(assigns, :form, Phoenix.Component.to_form(assigns.key_changeset, as: :key))

    ~H"""
    <div class="tw:bg-white tw:rounded-lg tw:shadow-sm tw:border tw:border-grey-200 tw:p-8">
      <%!-- Header --%>
      <div class="tw:mb-6">
        <h2 class="tw:text-xl tw:font-semibold tw:mb-2">Keys</h2>
        <p class="tw:text-sm tw:text-grey-500">
          Keys are used to authenticate and authorize clients to interact with the Hex API and repository.
        </p>
      </div>

      <%!-- Keys Table --%>
      <%= if @keys != [] do %>
        <.table>
          <:header>
            <th class="tw:px-0 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
              Name
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
              Permissions
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
              Last Use
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-right tw:text-sm tw:font-medium tw:text-grey-500">
              Actions
            </th>
          </:header>
          <:row :for={key <- @keys}>
            <.key_row key={key} csrf_token={@csrf_token} delete_key_path={@delete_key_path} />
          </:row>
        </.table>
      <% end %>

      <%!-- Generate New Key Button --%>
      <div>
        <.button
          variant="outline"
          size="md"
          phx-click={show_modal("generate-key-modal")}
          id="generate-key-button"
          class="tw:border-dashed"
        >
          <span class="tw:flex tw:items-center tw:gap-1">
            {icon(:heroicon, "plus", width: 14, height: 14)}
            <span>Generate New Key</span>
          </span>
        </.button>
      </div>
    </div>

    <%!-- Generate Key Modal --%>
    <.generate_key_modal
      form={@form}
      csrf_token={@csrf_token}
      create_key_path={@create_key_path}
      organizations={@organizations}
      packages={@packages}
      organization={assigns[:organization]}
    />

    <%!-- Key Generated Success Modal --%>
    <%= if @generated_key do %>
      <.key_generated_modal key={@generated_key} />
    <% end %>
    """
  end

  defp key_row(assigns) do
    modal_id = "revoke-key-#{assigns.key.id}"
    assigns = assign(assigns, :modal_id, modal_id)

    ~H"""
    <tr>
      <%!-- Name Column --%>
      <td class="tw:px-0 tw:py-4">
        <span class="tw:text-base tw:font-medium tw:text-grey-800">
          {@key.name}
        </span>
      </td>

      <%!-- Permissions Column --%>
      <td class="tw:px-4 tw:py-4">
        <div class="tw:flex tw:flex-wrap tw:gap-2">
          <%= for permission <- @key.permissions do %>
            <.badge variant={permission_variant(permission)}>
              {permission_name(permission)}
            </.badge>
          <% end %>
        </div>
      </td>

      <%!-- Last Use Column --%>
      <td class="tw:px-4 tw:py-4">
        <%= if @key.last_use && @key.last_use.used_at do %>
          <.tooltip text={last_use_details(@key.last_use)}>
            <span class="tw:text-sm tw:text-grey-600 tw:cursor-help">
              {pretty_date(@key.last_use.used_at)} ...
            </span>
          </.tooltip>
        <% end %>
      </td>

      <%!-- Actions Column --%>
      <td class="tw:px-4 tw:py-4">
        <div class="tw:flex tw:items-center tw:justify-end">
          <.tooltip text="Revoke key">
            <.icon_button
              phx-click={show_modal(@modal_id)}
              icon="trash"
              variant="danger"
              aria-label="Revoke key"
            />
          </.tooltip>
        </div>
      </td>
    </tr>

    <%!-- Revoke Key Modal --%>
    <.revoke_key_modal
      key={@key}
      csrf_token={@csrf_token}
      delete_key_path={@delete_key_path}
    />
    """
  end

  defp permission_name(%KeyPermission{domain: "api", resource: nil}), do: "API"
  defp permission_name(%KeyPermission{domain: "api", resource: resource}), do: "API:#{resource}"

  defp permission_name(%KeyPermission{domain: "repository", resource: resource}),
    do: "REPO:#{resource}"

  defp permission_name(%KeyPermission{domain: "package", resource: "hexpm/" <> resource}),
    do: "PKG:#{resource}"

  defp permission_name(%KeyPermission{domain: "package", resource: resource}),
    do: "PKG:#{resource}"

  defp permission_name(%KeyPermission{domain: "repositories"}), do: "REPOS"

  defp permission_variant(%KeyPermission{domain: "api"}), do: "green"
  defp permission_variant(%KeyPermission{domain: "repositories"}), do: "purple"
  defp permission_variant(%KeyPermission{domain: "repository"}), do: "purple"
  defp permission_variant(%KeyPermission{domain: "package"}), do: "default"

  defp last_use_details(last_use) do
    """
    Used at: #{pretty_datetime(last_use.used_at)}
    IP: #{last_use.ip}
    User agent: #{last_use.user_agent}
    """
  end
end
