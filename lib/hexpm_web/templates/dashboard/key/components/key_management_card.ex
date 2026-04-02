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
  attr :current_user, :map, required: true
  attr :create_key_path, :string, required: true
  attr :delete_key_path, :string, required: true
  attr :generated_key, :map, default: nil
  attr :organization, :map, default: nil

  def key_management_card(assigns) do
    assigns = assign(assigns, :form, Phoenix.Component.to_form(assigns.key_changeset, as: :key))

    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-grey-200 p-8">
      <%!-- Header --%>
      <div class="mb-6">
        <h2 class="text-xl font-semibold mb-2">Keys</h2>
        <p class="text-sm text-grey-500">
          Keys are used to authenticate and authorize clients to interact with the Hex API and repository.
        </p>
      </div>

      <%!-- Keys Table --%>
      <%= if @keys != [] do %>
        <.table>
          <:header>
            <th class="px-0 py-3 text-left text-sm font-medium text-grey-500">
              Name
            </th>
            <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">
              Permissions
            </th>
            <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">
              Last Use
            </th>
            <th class="px-4 py-3 text-right text-sm font-medium text-grey-500">
              Actions
            </th>
          </:header>
          <:row :for={key <- @keys}>
            <.key_row key={key} delete_key_path={@delete_key_path} />
          </:row>
        </.table>

        <%!-- Revoke Key Modals rendered outside the table to avoid invalid HTML inside <tbody> --%>
        <%= for key <- @keys do %>
          <.revoke_key_modal
            key={key}
            current_user={@current_user}
            delete_key_path={@delete_key_path}
          />
        <% end %>
      <% end %>

      <%!-- Generate New Key Button --%>
      <div>
        <.button
          variant="outline"
          size="md"
          phx-click={show_modal("generate-key-modal")}
          id="generate-key-button"
          class="border-dashed"
        >
          <span class="flex items-center gap-1">
            {icon(:heroicon, "plus", width: 14, height: 14)}
            <span>Generate New Key</span>
          </span>
        </.button>
      </div>
    </div>

    <%!-- Generate Key Modal --%>
    <.generate_key_modal
      form={@form}
      current_user={@current_user}
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
      <td class="px-0 py-4">
        <span class="text-base font-medium text-grey-800">
          {@key.name}
        </span>
      </td>

      <%!-- Permissions Column --%>
      <td class="px-4 py-4">
        <div class="flex flex-wrap gap-2">
          <%= for permission <- @key.permissions do %>
            <.badge variant={permission_variant(permission)}>
              {permission_name(permission)}
            </.badge>
          <% end %>
        </div>
      </td>

      <%!-- Last Use Column --%>
      <td class="px-4 py-4">
        <%= if @key.last_use && @key.last_use.used_at do %>
          <.tooltip text={last_use_details(@key.last_use)}>
            <span class="text-sm text-grey-600 cursor-help">
              {pretty_date(@key.last_use.used_at)} ...
            </span>
          </.tooltip>
        <% end %>
      </td>

      <%!-- Actions Column --%>
      <td class="px-4 py-4">
        <div class="flex items-center justify-end">
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
    "#{pretty_datetime(last_use.used_at)}\n#{last_use.ip}\n#{last_use.user_agent}"
  end
end
