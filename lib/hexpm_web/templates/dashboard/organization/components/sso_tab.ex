defmodule HexpmWeb.Dashboard.Organization.Components.SSOTab do
  use Phoenix.Component
  use HexpmWeb, :verified_routes

  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Input, only: [password_input: 1, text_input: 1]

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Connection

  attr :organization, :any, required: true
  attr :connection, :any, required: true
  attr :identities, :list, required: true
  attr :failures, :list, required: true
  attr :callback_url, :string, required: true
  attr :login_url, :string, required: true

  def sso_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-xl font-semibold text-grey-900 dark:text-grey-100">Single sign-on</h2>
        <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
          Configure a standards-based OpenID Connect provider. Okta is the documented pilot integration, and
          conventional Hexpm login remains available.
        </p>
      </div>

      <section class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5">
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Provider configuration</h3>
        <div class="mt-4 grid gap-4">
          <.readonly_value label="Redirect URI" value={@callback_url} />
          <.readonly_value label="Required scopes" value="openid email" />
          <.readonly_value
            :if={@connection && Connection.enabled?(@connection)}
            label="Organization login URL"
            value={@login_url}
          />
        </div>

        <.form
          :if={!@connection || !Connection.enabled?(@connection)}
          for={%{}}
          action={~p"/dashboard/orgs/#{@organization}/sso"}
          as={:sso}
          class="mt-5 space-y-4"
        >
          <.text_input
            id="sso-issuer"
            name="sso[issuer]"
            type="url"
            label="Issuer URL"
            value={@connection && @connection.issuer}
            required
          />
          <.text_input
            id="sso-client-id"
            name="sso[client_id]"
            label="Client ID"
            value={@connection && @connection.client_id}
            required
          />
          <.password_input
            id="sso-client-secret"
            name="sso[client_secret]"
            label={
              if @connection,
                do: "Client secret (leave blank to keep the current secret)",
                else: "Client secret"
            }
            required={!@connection}
          />
          <.button type="submit" variant="primary">Save configuration</.button>
        </.form>

        <div :if={@connection} class="mt-5 flex flex-wrap items-center gap-3">
          <span class={status_class(@connection)}>{status_label(@connection)}</span>

          <.form for={%{}} action={~p"/dashboard/orgs/#{@organization}/sso/test"}>
            <input type="hidden" name="secret_slot" value="active" />
            <.button type="submit" variant="secondary">Test connection</.button>
          </.form>

          <.form
            :if={@connection.tested_at && !Connection.enabled?(@connection)}
            for={%{}}
            action={~p"/dashboard/orgs/#{@organization}/sso/enable"}
          >
            <.button type="submit" variant="primary">Enable SSO login</.button>
          </.form>

          <.form
            :if={Connection.enabled?(@connection)}
            for={%{}}
            action={~p"/dashboard/orgs/#{@organization}/sso/disable"}
          >
            <.button type="submit" variant="danger">Disable SSO login</.button>
          </.form>
        </div>
      </section>

      <section
        :if={@connection}
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Client secret rotation</h3>
        <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
          Save and test a replacement while the active secret continues serving logins, then complete the rotation.
        </p>

        <.form
          for={%{}}
          action={~p"/dashboard/orgs/#{@organization}/sso/rotate"}
          as={:sso}
          class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end"
        >
          <div class="flex-1">
            <.password_input
              id="sso-rotation-secret"
              name="sso[client_secret]"
              label="Replacement client secret"
              required
            />
          </div>
          <.button type="submit" variant="secondary">Save replacement</.button>
        </.form>

        <div :if={@connection.pending_client_secret} class="mt-4 flex flex-wrap gap-3">
          <.form for={%{}} action={~p"/dashboard/orgs/#{@organization}/sso/test"}>
            <input type="hidden" name="secret_slot" value="pending" />
            <.button type="submit" variant="secondary">Test replacement</.button>
          </.form>
          <.form
            :if={@connection.pending_client_secret_tested_at}
            for={%{}}
            action={~p"/dashboard/orgs/#{@organization}/sso/promote"}
          >
            <.button type="submit" variant="primary">Complete rotation</.button>
          </.form>
        </div>
      </section>

      <section
        :if={@connection}
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Linked accounts</h3>
        <p :if={@identities == []} class="mt-3 text-sm text-grey-600 dark:text-grey-300">
          No accounts have linked through this connection.
        </p>
        <ul :if={@identities != []} class="mt-3 divide-y divide-grey-200 dark:divide-grey-800">
          <li :for={identity <- @identities} class="flex items-center justify-between gap-4 py-3">
            <span class="text-sm font-medium text-grey-900 dark:text-grey-100">{identity.user.username}</span>
            <.form for={%{}} action={~p"/dashboard/orgs/#{@organization}/sso/unlink"}>
              <input type="hidden" name="user_id" value={identity.user_id} />
              <.button type="submit" variant="danger" size="sm">Unlink</.button>
            </.form>
          </li>
        </ul>
      </section>

      <section
        :if={@connection}
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Recent failures</h3>
        <p :if={@failures == []} class="mt-3 text-sm text-grey-600 dark:text-grey-300">
          No recent SSO failures.
        </p>
        <ul :if={@failures != []} class="mt-3 space-y-3">
          <li :for={failure <- @failures} class="rounded-md bg-grey-50 dark:bg-grey-950 p-3 text-sm">
            <div class="font-medium text-grey-900 dark:text-grey-100">
              {SSO.failure_message(failure)}
            </div>
            <div class="mt-1 text-grey-500 dark:text-grey-400">
              {failure.stage}/{failure.code} · {Calendar.strftime(
                failure.inserted_at,
                "%Y-%m-%d %H:%M UTC"
              )}
            </div>
            <div :if={failure.user} class="mt-1 text-grey-700 dark:text-grey-200">
              {failure.user.username}
            </div>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp readonly_value(assigns) do
    ~H"""
    <div>
      <div class="text-sm font-medium text-grey-700 dark:text-grey-200">{@label}</div>
      <code class="mt-1 block overflow-x-auto rounded-md bg-grey-50 dark:bg-grey-950 px-3 py-2 text-sm text-grey-900 dark:text-grey-100">{@value}</code>
    </div>
    """
  end

  defp status_label(%Connection{enabled_at: nil, tested_at: nil}), do: "Not tested"
  defp status_label(%Connection{enabled_at: nil}), do: "Tested, disabled"
  defp status_label(%Connection{}), do: "Enabled"

  defp status_class(%Connection{enabled_at: nil}) do
    "rounded-full bg-grey-100 dark:bg-grey-800 px-3 py-1 text-xs font-medium text-grey-700 dark:text-grey-200"
  end

  defp status_class(%Connection{}) do
    "rounded-full bg-green-100 dark:bg-green-950 px-3 py-1 text-xs font-medium text-green-800 dark:text-green-200"
  end
end
