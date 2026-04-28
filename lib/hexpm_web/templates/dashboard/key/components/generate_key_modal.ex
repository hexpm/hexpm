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
    <.modal id="generate-key-modal" show={@form.source.action != nil}>
      <:header>
        <h2 class="text-lg font-semibold text-grey-900 dark:text-white">
          Generate New Key
        </h2>
      </:header>

      <.sudo_form current_user={@current_user} action={@create_key_path} id="generate-key-form">
        <%!-- Key Name --%>
        <div class="mb-6">
          <label class="block text-sm font-medium text-grey-700 dark:text-grey-300 mb-2">
            Key name
          </label>
          <.text_input field={@form[:name]} placeholder="Name" class="w-full" />
        </div>

        <%!-- Key Expiration --%>
        <div class="mb-6" phx-hook="KeyExpiry" id="key-expiry-group">
          <.select_input
            id="key-expires-in"
            name="key[expires_in]"
            label="Expiration"
            options={[
              {"7 days", "7"},
              {"30 days", "30"},
              {"60 days", "60"},
              {"90 days", "90"},
              {"1 year", "365"},
              {"Custom...", "custom"},
              {"No expiration", "none"}
            ]}
            value="30"
          />
          <div id="custom-expiry-input" class="hidden mt-2">
            <.text_input
              id="key-custom-expiry-date"
              name="key[custom_expiry_date]"
              type="date"
              placeholder="Select date"
              min={Date.utc_today() |> Date.add(1) |> Date.to_iso8601()}
              max="9999-12-31"
              class="w-full"
            />
          </div>
          <div id="no-expiry-warning" class="hidden mt-2 text-sm text-yellow-700 dark:text-yellow-400">
            For security, we recommend setting an expiration for your key.
          </div>
        </div>

        <%!-- Key Permissions --%>
        <div class="mb-6">
          <span class="block text-sm font-medium text-grey-700 dark:text-grey-300 mb-3">
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
              <span class="ml-2 text-sm text-grey-700 dark:text-grey-300 font-medium">API</span>
            </label>
            <div class="ml-6 space-y-2">
              <label class="flex items-center">
                <input
                  type="checkbox"
                  name="key[permissions][api][read]"
                  value="on"
                  class="child-checkbox rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">Read</span>
              </label>
              <label class="flex items-center">
                <input
                  type="checkbox"
                  name="key[permissions][api][write]"
                  value="on"
                  class="child-checkbox rounded border-grey-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">Write</span>
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
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">
                  Organization repository
                </span>
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
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300 font-medium">
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
                      <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">
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
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300 font-medium">
                  Packages
                </span>
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
                    <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">
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
