defmodule HexpmWeb.Dashboard.Key.Components.GenerateKeyModal do
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Input
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  alias Hexpm.Accounts.KeyGrantor
  alias Hexpm.Permissions

  attr :form, :map, required: true
  attr :current_user, :map, required: true
  attr :create_key_path, :string, required: true
  attr :packages, :list, required: true
  attr :organization, :map, default: nil
  attr :grantor, :any, default: nil

  @capabilities [
    {"publish", "Publish", "Publish, revert, retire and unretire releases, and publish docs"},
    {"owners", "Owners", "Add and remove package owners"},
    {"keys", "Keys", "Create keys with a subset of these permissions, and revoke keys"},
    {"members", "Members", "Add and remove members and change their roles"},
    {"administration", "Administration", "Change the number of seats"}
  ]

  def generate_key_modal(assigns) do
    assigns = assign(assigns, capabilities: @capabilities)

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
          <div :if={permission_errors(@form) != []} class="mb-3">
            <.errors errors={permission_errors(@form)} />
          </div>

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
                disabled={locked?(@grantor, "api")}
                class="rounded border-grey-300 text-purple-600 focus:ring-purple-500 disabled:opacity-50"
              />
              <span class="ml-2 text-sm text-grey-700 dark:text-grey-300 font-medium">API</span>
              <.role_hint grantor={@grantor} scope="api" />
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
                  disabled={locked?(@grantor, "api:write")}
                  data-locked={locked?(@grantor, "api:write")}
                  class="child-checkbox rounded border-grey-300 text-purple-600 focus:ring-purple-500 disabled:opacity-50"
                />
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">Write</span>
                <.role_hint grantor={@grantor} scope="api:write" />
              </label>
            </div>
          </div>

          <%!-- Capability Permissions --%>
          <div class="mb-4" id="capability-permissions">
            <span class="block text-sm text-grey-700 dark:text-grey-300 font-medium mb-1">
              Write permissions
            </span>
            <p class="text-xs text-grey-500 dark:text-grey-400 mb-2">
              Narrower than API write, which includes all of them.
            </p>
            <div class="ml-6 space-y-2">
              <label :for={{domain, label, description} <- @capabilities} class="flex items-start">
                <input
                  type="checkbox"
                  name={"key[permissions][capabilities][#{domain}]"}
                  value="on"
                  disabled={locked?(@grantor, domain)}
                  class="mt-0.5 rounded border-grey-300 text-purple-600 focus:ring-purple-500 disabled:opacity-50"
                />
                <span class="ml-2 text-sm text-grey-700 dark:text-grey-300">
                  {label}
                  <.role_hint grantor={@grantor} scope={domain} />
                  <span class="block text-xs text-grey-500 dark:text-grey-400">{description}</span>
                </span>
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
              <div class="ml-6 grid grid-cols-[minmax(0,1fr)_auto_auto_auto] items-center gap-x-6 gap-y-2">
                <span></span>
                <span class="text-xs font-medium text-grey-500 dark:text-grey-400">Manage</span>
                <span class="text-xs font-medium text-grey-500 dark:text-grey-400">Publish</span>
                <span class="text-xs font-medium text-grey-500 dark:text-grey-400">Owners</span>
                <%= for package <- @packages, resource = package_resource(@organization, package) do %>
                  <span class="text-sm text-grey-700 dark:text-grey-300 truncate">
                    {package.name}
                  </span>
                  <.package_checkbox domain="package" resource={resource} grantor={@grantor} />
                  <.package_checkbox domain="publish" resource={resource} grantor={@grantor} />
                  <.package_checkbox domain="owners" resource={resource} grantor={@grantor} />
                <% end %>
              </div>
              <p class="ml-6 mt-2 text-xs text-grey-500 dark:text-grey-400">
                Manage covers publishing and owners for the package.
              </p>
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

  defp permission_errors(%{source: %Ecto.Changeset{} = changeset}) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Map.get(:permissions, [])
    |> List.wrap()
    |> Enum.flat_map(fn
      %{} = errors -> errors |> Map.values() |> List.flatten()
      message -> [message]
    end)
    |> Enum.uniq()
  end

  defp permission_errors(_form), do: []

  attr :domain, :string, required: true
  attr :resource, :string, required: true
  attr :grantor, :any, required: true

  defp package_checkbox(assigns) do
    scope = "#{assigns.domain}:#{assigns.resource}"

    assigns =
      assign(assigns,
        locked: locked?(assigns.grantor, scope),
        role: required_role(assigns.grantor, scope)
      )

    ~H"""
    <label class="flex items-center" title={@role && "Requires #{@role}"}>
      <input
        type="checkbox"
        name={"key[permissions][#{@domain}][#{@resource}]"}
        value="on"
        disabled={@locked}
        aria-label={"#{@domain} #{@resource}"}
        class="rounded border-grey-300 text-purple-600 focus:ring-purple-500 disabled:opacity-50"
      />
    </label>
    """
  end

  attr :grantor, :any, required: true
  attr :scope, :string, required: true

  defp role_hint(assigns) do
    assigns = assign(assigns, :role, required_role(assigns.grantor, assigns.scope))

    ~H"""
    <span
      :if={@role}
      class="ml-2 inline-flex items-center rounded-full bg-grey-100 dark:bg-grey-700 px-2 py-0.5 text-xs font-medium text-grey-600 dark:text-grey-300"
    >
      Requires {@role}
    </span>
    """
  end

  # The role a permission needs when the viewer's role is below it, otherwise
  # nil. The server checks the same rule when the form is submitted.
  defp required_role(%KeyGrantor{} = grantor, scope) do
    permission = Permissions.scope_to_permission(scope)

    case KeyGrantor.check(grantor, permission) do
      :ok -> nil
      {:error, _message} -> if grantor.role, do: KeyGrantor.required_role(permission)
    end
  end

  defp required_role(nil, _scope), do: nil

  defp locked?(%KeyGrantor{} = grantor, scope),
    do: not KeyGrantor.grantable?(grantor, Permissions.scope_to_permission(scope))

  defp locked?(nil, _scope), do: false

  defp package_resource(nil, package), do: package.name
  defp package_resource(organization, package), do: "#{organization.name}/#{package.name}"
end
