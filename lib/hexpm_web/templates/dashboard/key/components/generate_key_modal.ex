defmodule HexpmWeb.Dashboard.Key.Components.GenerateKeyModal do
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Input
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  attr :form, :map, required: true
  attr :current_user, :map, required: true
  attr :create_key_path, :string, required: true
  attr :organizations, :list, required: true
  attr :packages, :list, required: true
  attr :organization, :map, default: nil

  def generate_key_modal(assigns) do
    ~H"""
    <.modal id="generate-key-modal">
      <:header>
        <h2 class="text-lg font-semibold text-grey-900">
          Generate New Key
        </h2>
      </:header>

      <.sudo_form current_user={@current_user} action={@create_key_path} id="generate-key-form">
        <%!-- Key Name --%>
        <div class="mb-6">
          <label class="block text-sm font-medium text-grey-700 mb-2">
            Key name
          </label>
          <.text_input field={@form[:name]} placeholder="Name" class="w-full" />
        </div>

        <%!-- Key Permissions --%>
        <div class="mb-6">
          <span class="block text-sm font-medium text-grey-700 mb-3">
            Key permissions
          </span>

          <%!-- API Permissions --%>
          <div
            class="mb-4"
            phx-hook="PermissionGroup"
            id="api-permission-group"
            data-parent="api-parent"
          >
            <label class="flex items-center mb-2">
              <input
                type="checkbox"
                id="api-parent"
                name="key[permissions][apis]"
                value="on"
                class="rounded border-grey-300 text-purple-600 focus:ring-purple-500"
              />
              <span class="ml-2 text-sm text-grey-700 font-medium">API</span>
            </label>
            <div class="ml-6 space-y-2">
              <label class="flex items-center">
                <input
                  type="checkbox"
                  name="key[permissions][api][read]"
                  value="on"
                  class="child-checkbox rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="ml-2 text-sm text-grey-700">Read</span>
              </label>
              <label class="flex items-center">
                <input
                  type="checkbox"
                  name="key[permissions][api][write]"
                  value="on"
                  class="child-checkbox rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="ml-2 text-sm text-grey-700">Write</span>
              </label>
            </div>
          </div>

          <%!-- Repository Permissions --%>
          <%= if @organization do %>
            <div class="mb-4">
              <label class="flex items-center">
                <input
                  type="checkbox"
                  name={"key[permissions][repository][#{@organization.name}]"}
                  value="on"
                  class="rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="ml-2 text-sm text-grey-700">Organization repository</span>
              </label>
            </div>
          <% else %>
            <div
              class="mb-4"
              phx-hook="PermissionGroup"
              id="repositories-permission-group"
              data-parent="repositories-parent"
            >
              <label class="flex items-center mb-2">
                <input
                  type="checkbox"
                  id="repositories-parent"
                  name="key[permissions][repositories]"
                  value="on"
                  class="rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="ml-2 text-sm text-grey-700 font-medium">
                  All Repositories
                </span>
              </label>
              <%= if @organizations != [] do %>
                <div class="ml-6 space-y-2">
                  <%= for organization <- @organizations do %>
                    <label class="flex items-center">
                      <input
                        type="checkbox"
                        name={"key[permissions][repository][#{organization.name}]"}
                        value="on"
                        class="child-checkbox rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                      />
                      <span class="ml-2 text-sm text-grey-700">
                        Repository: {organization.name}
                      </span>
                    </label>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- Package Permissions --%>
          <%= if @packages != [] do %>
            <div class="mb-4">
              <label class="flex items-center mb-2">
                <input
                  type="checkbox"
                  disabled
                  class="rounded border-grey-300 text-purple-600 focus:ring-purple-500 opacity-50"
                />
                <span class="ml-2 text-sm text-grey-700 font-medium">Packages</span>
              </label>
              <div class="ml-6 space-y-2">
                <%= for package <- @packages do %>
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      name={"key[permissions][package][#{package.name}]"}
                      value="on"
                      class="rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                    />
                    <span class="ml-2 text-sm text-grey-700">
                      Package: {package.name}
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </.sudo_form>

      <:footer>
        <div class="flex gap-3 justify-end">
          <.button phx-click={hide_modal("generate-key-modal")} variant="secondary">
            Cancel
          </.button>
          <.button type="submit" form="generate-key-form" variant="primary">
            Generate Key
          </.button>
        </div>
      </:footer>
    </.modal>
    """
  end
end
