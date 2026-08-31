defmodule HexpmWeb.Dashboard.Organization.Components.SSOTab do
  use Phoenix.Component
  use HexpmWeb, :verified_routes

  import HexpmWeb.Components.Buttons, only: [button: 1, button_link: 1]
  import HexpmWeb.Components.Input, only: [password_input: 1, select_input: 1, text_input: 1]

  alias Hexpm.Accounts.Keys
  alias Hexpm.Accounts.OrganizationDomain
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Connection

  attr :organization, :any, required: true
  attr :connection, :any, required: true
  attr :identities, :list, required: true
  attr :failures, :list, required: true
  attr :callback_url, :string, required: true
  attr :scim_base_url, :string, required: true
  attr :generated_scim_token, :any, default: nil
  attr :login_url, :string, required: true
  attr :domains, :list, default: []
  attr :personal_keys, :list, default: []
  attr :pending_personal_keys, :list, default: []
  attr :exempt_count, :integer, default: 0

  def sso_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div class="min-w-0 flex-1">
          <h2 class="text-xl font-semibold text-grey-900 dark:text-grey-100">Single sign-on</h2>
          <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
            Configure a standards-based OpenID Connect provider. Okta is the documented pilot integration, and
            conventional Hexpm login remains available.
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0 w-full sm:w-auto">
          <.button_link href={~p"/docs/organization-sso"} variant="outline" size="sm">
            Documentation
          </.button_link>
        </div>
      </div>

      <section class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5">
        <div class="flex items-start justify-between gap-4">
          <h3 class="font-semibold text-grey-900 dark:text-grey-100">Provider configuration</h3>
          <span :if={@connection} id="sso-connection-status" class={status_class(@connection)}>
            {status_label(@connection)}
          </span>
        </div>
        <div class="mt-4 grid gap-4">
          <.readonly_value label="Redirect URI" value={@callback_url} />
          <.readonly_value label="Required scopes" value="openid email" />
          <.readonly_value
            :if={@connection && Connection.enabled?(@connection)}
            label="Organization / Initiate Login URI"
            value={@login_url}
          />
        </div>
        <p class="mt-4 text-sm text-grey-600 dark:text-grey-300">
          For Okta, use the organization issuer such as <code>https://example.okta.com</code>,
          not the <code>/oauth2/default</code> authorization-server issuer. For Microsoft Entra,
          use the tenant-specific v2 issuer ending in <code>/&lt;tenant-id&gt;/v2.0</code>.
        </p>

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

        <div :if={@connection && !Connection.enabled?(@connection)} class="mt-5">
          <p class="text-sm text-grey-600 dark:text-grey-300">
            Removing the configuration deletes the stored client secret and every account
            linked through this connection. Members keep their Hexpm accounts and their
            membership of {@organization.name}.
          </p>

          <.form for={%{}} action={~p"/dashboard/orgs/#{@organization}/sso/delete"} class="mt-3">
            <.button type="submit" variant="danger">Remove SSO configuration</.button>
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
        id="sso-domains"
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Verified domains</h3>
        <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
          Proving you control a domain lets the organization admit people whose provider address is on
          it. Verification is re-checked daily, so a record that is taken down stops verifying.
        </p>

        <ul :if={@domains != []} class="mt-4 divide-y divide-grey-200 dark:divide-grey-800">
          <li :for={domain <- @domains} class="py-3">
            <div class="flex items-center justify-between gap-4">
              <div class="min-w-0">
                <div class="text-sm font-medium text-grey-900 dark:text-grey-100">
                  {domain.domain}
                </div>
                <div class="mt-1 text-xs text-grey-500 dark:text-grey-400">
                  {domain_status(domain)}
                </div>
              </div>
              <div class="flex flex-shrink-0 items-center gap-2">
                <.form
                  :if={!OrganizationDomain.verified?(domain)}
                  for={%{}}
                  action={~p"/dashboard/orgs/#{@organization}/sso/domains/verify"}
                >
                  <input type="hidden" name="domain_id" value={domain.id} />
                  <.button type="submit" variant="secondary" size="sm">Verify</.button>
                </.form>
                <.form for={%{}} action={~p"/dashboard/orgs/#{@organization}/sso/domains/remove"}>
                  <input type="hidden" name="domain_id" value={domain.id} />
                  <.button type="submit" variant="danger" size="sm">Remove</.button>
                </.form>
              </div>
            </div>

            <div :if={!OrganizationDomain.verified?(domain)} class="mt-3 grid gap-3">
              <.readonly_value label="TXT record name" value={OrganizationDomain.record_name(domain)} />
              <.readonly_value
                label="TXT record value"
                value={OrganizationDomain.record_value(domain)}
              />
            </div>
          </li>
        </ul>

        <.form
          for={%{}}
          action={~p"/dashboard/orgs/#{@organization}/sso/domains"}
          class="mt-4 flex flex-wrap items-end gap-3"
        >
          <div class="min-w-0 flex-1">
            <.text_input
              id="sso-domain"
              name="domain[domain]"
              label="Domain"
              placeholder="example.com"
              value=""
            />
          </div>
          <.button type="submit" variant="secondary">Add domain</.button>
        </.form>
      </section>

      <section
        :if={@connection}
        id="sso-jit"
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Just-in-time membership</h3>
        <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
          Adds an existing Hex account to the organization the first time it authenticates through
          your provider with an address on a verified domain. It never creates a Hex account, and
          people without one are reached with an invitation instead.
        </p>
        <p
          :if={@domains == [] or Enum.all?(@domains, &(!OrganizationDomain.verified?(&1)))}
          class="mt-3 text-sm text-grey-600 dark:text-grey-300"
        >
          Verify a domain first.
        </p>
        <p
          :if={Connection.jit_enabled?(@connection)}
          class="mt-3 text-sm text-grey-600 dark:text-grey-300"
        >
          While this is on, removing a member does not keep them out: their next login re-admits
          them. Remove their access at the identity provider instead.
        </p>

        <.form
          for={%{}}
          action={~p"/dashboard/orgs/#{@organization}/sso/jit"}
          as={:jit}
          class="mt-4 grid gap-4 sm:grid-cols-2"
        >
          <.select_input
            id="sso-jit-seat-policy"
            name="jit[jit_seat_policy]"
            label="When the seats run out"
            value={@connection.jit_seat_policy}
            options={[
              {"Off, do not add members automatically", ""},
              {"Refuse the login and notify administrators", "block"},
              {"Add a seat to the subscription", "expand"}
            ]}
            variant="light"
          />
          <.select_input
            id="sso-jit-role"
            name="jit[jit_role]"
            label="Role for new members"
            value={@connection.jit_role}
            options={[{"Read", "read"}, {"Write", "write"}, {"Admin", "admin"}]}
            variant="light"
          />
          <div class="sm:col-span-2">
            <.button type="submit" variant="secondary">Save</.button>
          </div>
        </.form>
      </section>

      <section
        :if={@connection}
        id="sso-scim"
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Provisioning (SCIM)</h3>
        <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
          Lets your provider create and deactivate members here as you assign and deactivate them
          there. Point its SCIM integration at the base URL below with the bearer token, which is
          shown once when generated. People without a Hex account are reached with an invitation;
          nothing here creates an account.
        </p>

        <div
          :if={@generated_scim_token}
          id="sso-scim-generated-token"
          class="mt-4 rounded-md border border-grey-200 dark:border-grey-800 bg-grey-50 dark:bg-grey-950 p-4"
        >
          <p class="text-sm font-medium text-grey-900 dark:text-grey-100">
            Copy the token now. It is not shown again.
          </p>
          <code class="mt-2 block break-all text-sm text-grey-900 dark:text-grey-100">
            {@generated_scim_token}
          </code>
        </div>

        <div class="mt-4 grid gap-4">
          <.readonly_value label="SCIM base URL" value={@scim_base_url} />
          <.readonly_value
            label="Status"
            value={if Connection.scim_enabled?(@connection), do: "On", else: "Off"}
          />
        </div>

        <.form
          for={%{}}
          action={
            if Connection.scim_enabled?(@connection),
              do: ~p"/dashboard/orgs/#{@organization}/sso/scim",
              else: ~p"/dashboard/orgs/#{@organization}/sso/scim/generate"
          }
          as={:scim}
          class="mt-4 grid gap-4 sm:grid-cols-2"
        >
          <.select_input
            id="sso-scim-seat-policy"
            name="scim[scim_seat_policy]"
            label="When the seats run out"
            value={@connection.scim_seat_policy}
            options={[
              {"Choose what happens", ""},
              {"Refuse the create and notify administrators", "block"},
              {"Add a seat to the subscription", "expand"}
            ]}
            variant="light"
          />
          <.select_input
            id="sso-scim-role"
            name="scim[scim_role]"
            label="Role for provisioned members"
            value={@connection.scim_role}
            options={[{"Read", "read"}, {"Write", "write"}, {"Admin", "admin"}]}
            variant="light"
          />
          <div class="sm:col-span-2">
            <.button type="submit" variant="secondary">
              {if Connection.scim_enabled?(@connection),
                do: "Save settings",
                else: "Save and generate token"}
            </.button>
          </div>
        </.form>

        <div :if={Connection.scim_enabled?(@connection)} class="mt-4 flex gap-3">
          <.form
            for={%{}}
            action={~p"/dashboard/orgs/#{@organization}/sso/scim/generate"}
            as={:scim}
          >
            <input type="hidden" name="scim[scim_seat_policy]" value={@connection.scim_seat_policy} />
            <input type="hidden" name="scim[scim_role]" value={@connection.scim_role} />
            <.button type="submit" variant="outline">Regenerate token</.button>
          </.form>
          <.form
            for={%{}}
            action={~p"/dashboard/orgs/#{@organization}/sso/scim/delete"}
            as={:scim}
          >
            <.button type="submit" variant="outline">Turn provisioning off</.button>
          </.form>
        </div>
      </section>

      <section
        :if={@connection}
        id="sso-enforcement"
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Enforcement</h3>
        <p class="mt-2 text-sm text-grey-600 dark:text-grey-300">
          Decides whether members have to authenticate through your provider to reach this
          organization. Optional asks nobody. Pilot asks only the members you mark as enforced on
          the members tab. Required asks everyone except the exemptions listed there.
        </p>

        <.form
          for={%{}}
          action={~p"/dashboard/orgs/#{@organization}/sso/enforcement"}
          as={:enforcement}
          class="mt-4 grid gap-4 sm:grid-cols-2"
        >
          <.select_input
            id="sso-enforcement-mode"
            name="enforcement[enforcement_mode]"
            label="Mode"
            value={@connection.enforcement_mode}
            options={[{"Optional", "optional"}, {"Pilot", "pilot"}, {"Required", "required"}]}
            variant="light"
          />
          <.select_input
            id="sso-enforcement-personal-keys"
            name="enforcement[personal_keys]"
            label="Personal API keys"
            value={@connection.personal_keys || "allow"}
            options={[
              {"Allow them, and list them below", "allow"},
              {"Block them from reaching this organization", "block"}
            ]}
            variant="light"
          />
          <.select_input
            id="sso-enforcement-lifetime"
            name="enforcement[session_lifetime_seconds]"
            label="How long an authentication lasts"
            value={to_string(@connection.session_lifetime_seconds)}
            options={[
              {"1 hour", "3600"},
              {"8 hours", "28800"},
              {"24 hours", "86400"},
              {"7 days", "604800"},
              {"30 days", "2592000"}
            ]}
            variant="light"
          />
          <.text_input
            id="sso-enforcement-required-at"
            name="enforcement[required_at]"
            label="Required from"
            type="date"
            value={required_at_value(@connection)}
          />
          <p class="sm:col-span-2 text-sm text-grey-600 dark:text-grey-300">
            The lifetime governs every path. A member on the web re-authenticates with a redirect;
            at a terminal the CLI asks them to re-authenticate in a browser and keeps the session it
            already has. Continuous integration is unaffected either way, because it authenticates
            with an organization key rather than as a person.
          </p>
          <div class="sm:col-span-2">
            <.button type="submit" variant="secondary">Save</.button>
          </div>
        </.form>

        <div class="mt-6 border-t border-grey-200 dark:border-grey-800 pt-4">
          <h4 class="text-sm font-semibold text-grey-900 dark:text-grey-100">
            What enforcement does not cover
          </h4>
          <ul class="mt-2 space-y-2 text-sm text-grey-600 dark:text-grey-300">
            <li>
              <span class="font-medium">Organization API keys.</span>
              These authenticate as the organization rather than as a person, which is what makes
              continuous integration work, so SSO never applies to them. Revoke the key to revoke
              the access.
            </li>
            <li :if={@connection.personal_keys != "block"}>
              <span class="font-medium">Personal API keys.</span>
              They are static credentials with nothing to expire them and nothing for your
              provider's policy to evaluate, and they keep reaching this organization regardless of
              enforcement. Removing the member here still takes their keys with it.
            </li>
            <li :if={@exempt_count > 0}>
              <span class="font-medium">
                Exempt members ({@exempt_count}).
              </span>
              They reach this organization on a Hex password alone. The members tab names them.
            </li>
            <li>
              <span class="font-medium">Billing and this page.</span>
              Both stay reachable without authenticating, so a broken connection can be repaired
              and the subscription does not lapse while you are locked out. Reaching them that way
              is recorded in the audit log and mailed to the administrators.
            </li>
            <li>
              <span class="font-medium">Offboarding takes time.</span>
              Removing a member here stops new access within 30 minutes, bounded by how long an
              already-issued token lives. Deactivating someone only at your provider takes until
              their authentication lapses, which is the lifetime set above.
            </li>
          </ul>
        </div>

        <.personal_key_table
          :if={@personal_keys != []}
          heading={personal_keys_heading(@connection)}
          keys={@personal_keys}
          organization={@organization}
        />

        <.personal_key_table
          :if={@pending_personal_keys != []}
          heading={pending_keys_heading(@connection)}
          keys={@pending_personal_keys}
          organization={@organization}
        >
          These members follow the organization's mode rather than a per-member setting, so they
          keep their access until the date above and lose it on it.
        </.personal_key_table>
      </section>

      <section
        :if={@connection}
        id="sso-linked-accounts"
        class="rounded-lg border border-grey-200 dark:border-grey-800 bg-white dark:bg-grey-900 p-5"
      >
        <h3 class="font-semibold text-grey-900 dark:text-grey-100">Linked accounts</h3>
        <p :if={@identities == []} class="mt-3 text-sm text-grey-600 dark:text-grey-300">
          No accounts have linked through this connection.
        </p>
        <ul :if={@identities != []} class="mt-3 divide-y divide-grey-200 dark:divide-grey-800">
          <li :for={identity <- @identities} class="flex items-center justify-between gap-4 py-3">
            <div class="min-w-0">
              <a
                href={~p"/users/#{identity.user}"}
                class="text-sm font-medium text-grey-900 transition-colors hover:text-primary-600 dark:text-grey-100"
              >
                {identity.user.username}
              </a>
              <div class="mt-1 text-xs text-grey-500 dark:text-grey-400">
                {last_authenticated(identity.last_authenticated_at)}
              </div>
            </div>
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

  attr :heading, :string, required: true
  attr :keys, :list, required: true
  attr :organization, :any, required: true
  slot :inner_block

  defp personal_key_table(assigns) do
    ~H"""
    <div class="mt-6">
      <h4 class="text-sm font-semibold text-grey-900 dark:text-grey-100">{@heading}</h4>
      <p :if={@inner_block != []} class="mt-1 text-sm text-grey-600 dark:text-grey-300">
        {render_slot(@inner_block)}
      </p>
      <table class="mt-2 w-full text-sm">
        <thead class="text-left text-grey-500 dark:text-grey-400">
          <tr>
            <th class="py-1 font-medium">Member</th>
            <th class="py-1 font-medium">Key</th>
            <th class="py-1 font-medium">How it reaches this organization</th>
            <th class="py-1 font-medium">Key last used</th>
          </tr>
        </thead>
        <tbody class="text-grey-700 dark:text-grey-200">
          <tr :for={key <- @keys} class="border-t border-grey-100 dark:border-grey-800">
            <td class="py-1">{key.user.username}</td>
            <td class="py-1">{key.name}</td>
            <td class="py-1">{reach_description(key, @organization)}</td>
            <td class="py-1">{last_used(key)}</td>
          </tr>
        </tbody>
      </table>
      <p class="mt-2 text-xs text-grey-500 dark:text-grey-400">
        A key records when it was last used but not what it was used for, so this date is the
        key's last use anywhere on Hex rather than its last use against this organization.
      </p>
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

  defp domain_status(%OrganizationDomain{verified_at: nil}) do
    "Not verified yet. Publish the TXT record below, then verify."
  end

  defp domain_status(%OrganizationDomain{verified_at: verified_at}) do
    "Verified on #{Calendar.strftime(verified_at, "%Y-%m-%d")}"
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

  defp last_authenticated(nil), do: "Never authenticated through this connection"

  defp last_authenticated(authenticated_at) do
    "Last authenticated #{Calendar.strftime(authenticated_at, "%Y-%m-%d %H:%M UTC")}"
  end

  defp required_at_value(%Connection{required_at: nil}), do: ""

  defp required_at_value(%Connection{required_at: required_at}) do
    Calendar.strftime(required_at, "%Y-%m-%d")
  end

  defp personal_keys_heading(%Connection{} = connection) do
    if Connection.blocks_personal_keys?(connection) do
      "Personal API keys this organization already turns away"
    else
      "Personal API keys that reach this organization"
    end
  end

  defp pending_keys_heading(%Connection{required_at: required_at}) when not is_nil(required_at) do
    "Personal API keys that lose access on " <> Calendar.strftime(required_at, "%Y-%m-%d")
  end

  defp reach_description(key, organization) do
    cond do
      Keys.names_organization?(key, organization) -> "Named in the key"
      Enum.any?(key.permissions, &(&1.domain == "repositories")) -> "Through every repository"
      true -> "Through the key's API access"
    end
  end

  defp last_used(%{last_use: %{used_at: used_at}}) when not is_nil(used_at) do
    Calendar.strftime(used_at, "%Y-%m-%d")
  end

  defp last_used(_key), do: "Never"
end
