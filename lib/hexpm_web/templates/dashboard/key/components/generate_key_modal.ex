defmodule HexpmWeb.Dashboard.Key.Components.GenerateKeyModal do
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Input

  attr :form, :map, required: true
  attr :csrf_token, :string, required: true
  attr :create_key_path, :string, required: true
  attr :organizations, :list, required: true
  attr :packages, :list, required: true
  attr :organization, :map, default: nil

  def generate_key_modal(assigns) do
    ~H"""
    <.modal id="generate-key-modal">
      <:header>
        <h2 class="tw:text-lg tw:font-semibold tw:text-grey-900">
          Generate New Key
        </h2>
      </:header>

      <form action={@create_key_path} method="post" id="generate-key-form">
        <input type="hidden" name="_csrf_token" value={@csrf_token} />

        <%!-- Key Name --%>
        <div class="tw:mb-6">
          <label class="tw:block tw:text-sm tw:font-medium tw:text-grey-700 tw:mb-2">
            Key name
          </label>
          <.text_input field={@form[:name]} placeholder="Name" class="tw:w-full" />
        </div>

        <%!-- Key Permissions --%>
        <div class="tw:mb-6">
          <span class="tw:block tw:text-sm tw:font-medium tw:text-grey-700 tw:mb-3">
            Key permissions
          </span>

          <%!-- API Permissions --%>
          <div class="tw:mb-4" phx-hook="PermissionGroup" id="api-permission-group" data-parent="api-parent">
            <label class="tw:flex tw:items-center tw:mb-2">
              <input
                type="checkbox"
                id="api-parent"
                name="key[permissions][apis]"
                value="on"
                class="tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
              />
              <span class="tw:ml-2 tw:text-sm tw:text-grey-700 tw:font-medium">API</span>
            </label>
            <div class="tw:ml-6 tw:space-y-2">
              <label class="tw:flex tw:items-center">
                <input
                  type="checkbox"
                  name="key[permissions][api][read]"
                  value="on"
                  class="child-checkbox tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
                />
                <span class="tw:ml-2 tw:text-sm tw:text-grey-700">Read</span>
              </label>
              <label class="tw:flex tw:items-center">
                <input
                  type="checkbox"
                  name="key[permissions][api][write]"
                  value="on"
                  class="child-checkbox tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
                />
                <span class="tw:ml-2 tw:text-sm tw:text-grey-700">Write</span>
              </label>
            </div>
          </div>

          <%!-- Repository Permissions --%>
          <%= if @organization do %>
            <label class="tw:flex tw:items-center">
              <input
                type="checkbox"
                name={"key[permissions][repository][#{@organization.name}]"}
                value="on"
                class="tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
              />
              <span class="tw:ml-2 tw:text-sm tw:text-grey-700">Organization repository</span>
            </label>
          <% else %>
            <div
              class="tw:mb-4"
              phx-hook="PermissionGroup"
              id="repositories-permission-group"
              data-parent="repositories-parent"
            >
              <label class="tw:flex tw:items-center tw:mb-2">
                <input
                  type="checkbox"
                  id="repositories-parent"
                  name="key[permissions][repositories]"
                  value="on"
                  class="tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
                />
                <span class="tw:ml-2 tw:text-sm tw:text-grey-700 tw:font-medium">
                  All Repositories
                </span>
              </label>
              <%= if @organizations != [] do %>
                <div class="tw:ml-6 tw:space-y-2">
                  <%= for organization <- @organizations do %>
                    <label class="tw:flex tw:items-center">
                      <input
                        type="checkbox"
                        name={"key[permissions][repository][#{organization.name}]"}
                        value="on"
                        class="child-checkbox tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
                      />
                      <span class="tw:ml-2 tw:text-sm tw:text-grey-700">
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
            <div class="tw:mb-4">
              <label class="tw:flex tw:items-center tw:mb-2">
                <input
                  type="checkbox"
                  disabled
                  class="tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500 tw:opacity-50"
                />
                <span class="tw:ml-2 tw:text-sm tw:text-grey-700 tw:font-medium">Packages</span>
              </label>
              <div class="tw:ml-6 tw:space-y-2">
                <%= for package <- @packages do %>
                  <label class="tw:flex tw:items-center">
                    <input
                      type="checkbox"
                      name={"key[permissions][package][#{package.name}]"}
                      value="on"
                      class="tw:rounded tw:border-grey-300 tw:text-purple-600 focus:tw:ring-purple-500"
                    />
                    <span class="tw:ml-2 tw:text-sm tw:text-grey-700">
                      Package: {package.name}
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </form>

      <:footer>
        <div class="tw:flex tw:gap-3 tw:justify-end">
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
