defmodule HexpmWeb.Dashboard.Organization.Components.CreateOrganizationModal do
  @moduledoc """
  Modal for creating a new organization from anywhere in the dashboard sidebar.
  Submits to POST /dashboard/orgs — the existing create action handles it.
  """
  use Phoenix.Component
  import HexpmWeb.Components.Modal, only: [modal: 1, hide_modal: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1]

  @modal_id "create-organization-modal"

  def modal_id, do: @modal_id

  attr :changeset, :any, required: true

  def create_organization_modal(assigns) do
    ~H"""
    <.modal id={modal_id()} title="Create New Organization" max_width="md">
      <p class="text-sm text-grey-500 mb-6">
        With organizations you can manage public packages with fine-grained
        access control for your members. Private packages are available on
        paid plans at <strong class="text-grey-700">$7.00 per user / month</strong>.
      </p>

      <form id="create-org-form" action="/dashboard/orgs" method="post">
        <input
          type="hidden"
          name="_csrf_token"
          value={Plug.CSRFProtection.get_csrf_token()}
        />

        <div class="mb-6">
          <label
            for="org-name-input"
            class="block text-sm font-medium text-grey-700 mb-1"
          >
            Organization name
          </label>
          <input
            id="org-name-input"
            type="text"
            name="organization[name]"
            placeholder="my-organization"
            pattern="[a-z][a-z0-9_]*"
            required
            autocomplete="off"
            class="w-full h-10 px-3 border border-grey-300 rounded-lg text-sm text-grey-900 placeholder:text-grey-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
          <p class="mt-1.5 text-xs text-grey-500">
            Only lowercase letters, numbers, and underscores. Used in
            <code class="font-mono bg-grey-100 px-1 rounded">mix.exs</code>
            dependencies.
          </p>

          <%= if @changeset.action do %>
            <%= for {msg, _opts} <- Keyword.get_values(@changeset.errors, :name) do %>
              <p class="mt-1.5 text-xs text-red-600">{msg}</p>
            <% end %>
          <% end %>
        </div>

        <div class="flex items-center justify-end gap-3">
          <.button
            type="button"
            variant="secondary"
            phx-click={hide_modal(modal_id())}
          >
            Cancel
          </.button>
          <.button type="submit" variant="primary">
            Create Organization
          </.button>
        </div>
      </form>
    </.modal>
    """
  end
end
