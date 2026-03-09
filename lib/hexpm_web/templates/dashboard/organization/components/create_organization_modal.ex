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
      <p class="tw:text-sm tw:text-grey-500 tw:mb-6">
        With organizations you can manage public packages with fine-grained
        access control for your members. Private packages are available on
        paid plans at <strong class="tw:text-grey-700">$7.00 per user / month</strong>.
      </p>

      <form id="create-org-form" action="/dashboard/orgs" method="post">
        <input
          type="hidden"
          name="_csrf_token"
          value={Plug.CSRFProtection.get_csrf_token()}
        />

        <div class="tw:mb-6">
          <label
            for="org-name-input"
            class="tw:block tw:text-sm tw:font-medium tw:text-grey-700 tw:mb-1"
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
            class="tw:w-full tw:h-10 tw:px-3 tw:border tw:border-grey-300 tw:rounded-lg tw:text-sm tw:text-grey-900 tw:placeholder:text-grey-400 tw:focus:outline-none tw:focus:ring-2 tw:focus:ring-purple-500 tw:focus:border-transparent"
          />
          <p class="tw:mt-1.5 tw:text-xs tw:text-grey-500">
            Only lowercase letters, numbers, and underscores. Used in
            <code class="tw:font-mono tw:bg-grey-100 tw:px-1 tw:rounded">mix.exs</code>
            dependencies.
          </p>

          <%= if @changeset.action do %>
            <%= for {msg, _opts} <- Keyword.get_values(@changeset.errors, :name) do %>
              <p class="tw:mt-1.5 tw:text-xs tw:text-red-600">{msg}</p>
            <% end %>
          <% end %>
        </div>

        <div class="tw:flex tw:items-center tw:justify-end tw:gap-3">
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
