defmodule HexpmWeb.Dashboard.Organization.Components.WorkloadIdentitiesTab do
  @moduledoc """
  Workload identities tab content for the organization dashboard. Lists the
  GitHub Actions workflows that can fetch from the organization's repository,
  and with the write role publish to it and publish the public packages the
  organization owns. Admins with 2FA on their account add and remove them.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Badge, only: [badge: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1, button_link: 1, icon_button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  import HexpmWeb.Components.Input,
    only: [errors: 1, field_errors: 2, text_input: 1, select_input: 1]

  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]
  import HexpmWeb.Components.Tooltip, only: [tooltip: 1]

  alias Hexpm.Accounts.{Organization, User}
  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  attr :changeset, :any, required: true
  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :workload_identities, :list, required: true

  def workload_identities_tab(assigns) do
    assigns =
      assigns
      |> assign(:admin?, admin?(assigns.current_user, assigns.organization))
      |> assign(:tfa?, User.tfa_enabled?(assigns.current_user))
      |> assign(:billing?, Organization.billing_active?(assigns.organization))
      |> assign(:form, to_form(assigns.changeset, as: :workload_identity))

    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">Workload identities</h2>
          <p class="text-grey-500 dark:text-grey-300 text-sm mt-1">
            GitHub Actions workflows that fetch packages from the {@organization.name} repository without an API key. With the write role they also publish and create packages in it, and can publish the public packages {@organization.name} owns.
            <a
              href={~p"/docs/workload-identity" <> "#organization-workload-identities"}
              class="text-primary-600 dark:text-primary-300 hover:underline"
            >
              Learn more
            </a>
          </p>
        </div>

        <ul class="divide-y divide-grey-100 dark:divide-grey-700">
          <li
            :for={workload_identity <- @workload_identities}
            id={"workload-identity-#{workload_identity.id}"}
            class="flex items-center justify-between gap-3 px-6 py-4"
          >
            <div class="min-w-0 space-y-1">
              <p class="flex flex-wrap items-center gap-2 text-sm font-medium text-grey-900 dark:text-white">
                <span class="break-all">{repository_label(workload_identity)}</span>
                <.badge variant={role_variant(workload_identity.role)}>
                  {workload_identity.role}
                </.badge>
              </p>
              <p class="text-xs text-grey-500 dark:text-grey-300">
                Workflow: {workflow_label(workload_identity.workflow)}
                <span aria-hidden="true">&middot;</span>
                Environment: {environment_label(workload_identity.environment)}
              </p>
              <p
                :if={workload_identity.role == "write" and workload_identity.covers_private}
                class="text-xs text-grey-500 dark:text-grey-300"
              >
                Private: {private_label(workload_identity.packages)}
              </p>
              <p
                :if={workload_identity.role == "write" and workload_identity.covers_public}
                class="text-xs text-grey-500 dark:text-grey-300"
              >
                Public: {public_label(workload_identity.public_packages)}
              </p>
            </div>

            <.icon_button
              :if={@admin? and @tfa?}
              icon="x-mark"
              variant="danger"
              aria-label={"Remove workload identity #{repository_label(workload_identity)}"}
              phx-click={show_modal("remove-workload-identity-#{workload_identity.id}")}
            />
            <.tooltip :if={@admin? and not @tfa?} text="Requires 2FA">
              <.icon_button
                icon="x-mark"
                variant="danger"
                aria-label={"Remove workload identity #{repository_label(workload_identity)}"}
                disabled
              />
            </.tooltip>
          </li>
          <li
            :if={@workload_identities == []}
            class="px-6 py-4 text-sm text-grey-500 dark:text-grey-300"
          >
            No workload identities configured for this organization.
          </li>
        </ul>

        <p
          :if={not @admin?}
          class="px-6 py-3 border-t border-grey-200 dark:border-grey-700 bg-grey-50 dark:bg-grey-900 text-sm text-grey-600 dark:text-grey-300"
        >
          Only organization admins can add and remove workload identities.
        </p>
      </div>

      <div
        :if={@admin?}
        class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden"
      >
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">
            Add workload identity
          </h2>
        </div>

        <div
          :if={not @tfa?}
          class="mx-6 mt-5 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 px-4 py-3"
        >
          <p class="text-sm text-amber-900 dark:text-amber-100">
            Two-factor authentication on your account is required to add or remove workload identities.
          </p>
          <.button_link
            href={
              ~p"/dashboard/security?return=#{~p"/dashboard/orgs/#{@organization}/workload-identities"}"
            }
            size="sm"
            class="shrink-0"
          >
            Enable two-factor authentication
          </.button_link>
        </div>

        <p
          :if={not @billing?}
          id="workload-identity-billing-note"
          class="mx-6 mt-5 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 px-4 py-3 text-sm text-amber-900 dark:text-amber-100"
        >
          Private packages and the read role need an active billing subscription. Public packages {@organization.name} owns don't.
          <a href={~p"/dashboard/orgs/#{@organization}/billing"} class="font-medium underline">
            Billing
          </a>
        </p>

        <.sudo_form
          current_user={@current_user}
          action={~p"/dashboard/orgs/#{@organization}/workload-identities"}
          method="post"
          id="add-workload-identity-form"
          class="group/workload-identity px-6 py-5 flex flex-col gap-4"
        >
          <fieldset disabled={not @tfa?} class="flex flex-col gap-4 disabled:opacity-50">
            <input type="hidden" name="workload_identity[provider]" value="github" />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.text_input
                field={@form[:repository_owner]}
                label="Repository owner"
                placeholder="acme"
                required
              />
              <.text_input
                field={@form[:repository]}
                value={WorkloadIdentity.repository_name(@form[:repository].value)}
                label="Repository name"
                placeholder="widget"
              />
              <.select_input
                field={@form[:role]}
                label="Role"
                options={[
                  {"Read: fetch packages", "read"},
                  {"Write: fetch, publish and create packages", "write"}
                ]}
                disabled_options={if @billing?, do: [], else: ["read"]}
              />
              <.text_input
                field={@form[:workflow]}
                label="Workflow"
                placeholder="release.yml"
              />
              <.text_input
                field={@form[:environment]}
                label="Environment"
                placeholder="Any"
              />
              <.text_input
                field={@form[:repository_id]}
                label="Repository ID"
                placeholder="123456"
              />
            </div>

            <div class="flex flex-col gap-3">
              <div class="group/private rounded-lg border border-grey-200 dark:border-grey-700 p-4 flex flex-col gap-3">
                <label class={[
                  "hidden group-has-[option[value=write]:checked]/workload-identity:flex items-start gap-3",
                  if(@billing?, do: "cursor-pointer", else: "cursor-not-allowed opacity-50")
                ]}>
                  <input type="hidden" name="workload_identity[covers_private]" value="false" />
                  <input
                    type="checkbox"
                    id="workload_identity_covers_private"
                    name="workload_identity[covers_private]"
                    value="true"
                    checked={@billing? and checked?(@form[:covers_private].value)}
                    disabled={not @billing?}
                    class="mt-0.5 w-4 h-4 text-purple-600 border-grey-300 dark:border-grey-600 rounded focus:ring-2 focus:ring-purple-500"
                  />
                  <span class="flex flex-col gap-0.5">
                    <span class="text-small font-medium text-grey-900 dark:text-grey-100">
                      Private packages
                    </span>
                    <span class="text-xs text-grey-500 dark:text-grey-300">
                      Packages in the {@organization.name} repository.
                      <span :if={not @billing?}>Needs an active billing subscription.</span>
                    </span>
                  </span>
                </label>
                <div class="group-has-[option[value=write]:checked]/workload-identity:hidden flex flex-col gap-0.5">
                  <span class="text-small font-medium text-grey-900 dark:text-grey-100">
                    Private packages
                  </span>
                  <span class="text-xs text-grey-500 dark:text-grey-300">
                    The read role fetches every package in the {@organization.name} repository.
                  </span>
                </div>
                <div class="hidden group-has-[option[value=write]:checked]/workload-identity:group-has-[:checked]/private:block">
                  <.text_input
                    field={@form[:packages]}
                    value={names_value(@form, :packages)}
                    label="Private package names"
                    placeholder="All packages in the repository"
                  />
                  <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
                    Package names separated by commas. A name can be a package that doesn't exist yet, which the workflow can then create. Leave empty to cover every package in the repository.
                  </p>
                </div>
              </div>

              <div class="group/public rounded-lg border border-grey-200 dark:border-grey-700 p-4 flex flex-col gap-3">
                <label class="flex items-start gap-3 cursor-pointer group-has-[option[value=read]:checked]/workload-identity:cursor-not-allowed group-has-[option[value=read]:checked]/workload-identity:opacity-50">
                  <input type="hidden" name="workload_identity[covers_public]" value="false" />
                  <input
                    type="checkbox"
                    id="workload_identity_covers_public"
                    name="workload_identity[covers_public]"
                    value="true"
                    checked={checked?(@form[:covers_public].value)}
                    class="mt-0.5 w-4 h-4 text-purple-600 border-grey-300 dark:border-grey-600 rounded focus:ring-2 focus:ring-purple-500 group-has-[option[value=read]:checked]/workload-identity:pointer-events-none"
                  />
                  <span class="flex flex-col gap-0.5">
                    <span class="text-small font-medium text-grey-900 dark:text-grey-100">
                      Public packages
                    </span>
                    <span class="text-xs text-grey-500 dark:text-grey-300">
                      Public packages on hex.pm that {@organization.name} owns.
                    </span>
                  </span>
                </label>
                <p class="group-has-[option[value=write]:checked]/workload-identity:hidden text-xs text-grey-500 dark:text-grey-300">
                  Only the write role covers public packages. Public packages need no credentials to fetch.
                </p>
                <div class="hidden group-has-[option[value=write]:checked]/workload-identity:group-has-[:checked]/public:block">
                  <.text_input
                    field={@form[:public_packages]}
                    value={names_value(@form, :public_packages)}
                    label="Public package names"
                    placeholder={"All public packages #{@organization.name} owns"}
                  />
                  <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
                    Names of public packages {@organization.name} owns, separated by commas. Leave empty to cover every public package {@organization.name} owns, including packages it becomes an owner of later. Workload identities don't create public packages, so publish a package's first release with a user account or an API key. Each public release shows the GitHub repository, workflow and actor that published it, also when the repository is private.
                  </p>
                </div>
              </div>

              <.errors errors={field_errors(@form, :covers_private)} />
            </div>

            <div class="flex flex-col gap-2 text-xs text-grey-500 dark:text-grey-300">
              <p>
                The write role needs a repository name and a workflow, an environment when the repository is public, and private packages, public packages or both. Private packages and the read role need an active billing subscription. With the read role, an empty workflow matches every workflow in the repository, and an empty repository name matches every repository the owner has, for example so all of them can fetch private dependencies.
              </p>
              <p>
                Anyone who can push a workflow file to a matching repository can then fetch, the same as with an organization key stored as a GitHub secret. Set an environment with protection rules to narrow a single repository.
              </p>
              <p>
                The repository ID is required for private GitHub repositories Hex can't see. Find it with <code class="text-xs">gh api repos/OWNER/NAME --jq .id</code>.
              </p>
            </div>
          </fieldset>

          <div class="flex justify-end">
            <.button :if={@tfa?} type="submit" variant="primary">Add workload identity</.button>
            <.tooltip :if={not @tfa?} text="Requires 2FA">
              <.button type="submit" variant="primary" disabled>Add workload identity</.button>
            </.tooltip>
          </div>
        </.sudo_form>
      </div>

      <.modal
        :for={workload_identity <- @workload_identities}
        :if={@admin? and @tfa?}
        id={"remove-workload-identity-#{workload_identity.id}"}
        title="Remove workload identity?"
        max_width="md"
      >
        <p class="text-sm text-grey-600 dark:text-grey-300">
          Workflows in
          <strong class="font-semibold text-grey-900 dark:text-white">
            {repository_label(workload_identity)}
          </strong>
          that match this workload identity can no longer get Hex tokens for {@organization.name}. Tokens they already have keep working at repo.hex.pm until they expire, at most 15 minutes.
        </p>

        <.sudo_form
          current_user={@current_user}
          action={~p"/dashboard/orgs/#{@organization}/workload-identities/#{workload_identity.id}"}
          method="delete"
          id={"remove-workload-identity-form-#{workload_identity.id}"}
          class="mt-6 flex justify-end gap-3"
        >
          <.button
            type="button"
            variant="secondary"
            phx-click={hide_modal("remove-workload-identity-#{workload_identity.id}")}
          >
            Cancel
          </.button>
          <.button type="submit" variant="danger">Remove workload identity</.button>
        </.sudo_form>
      </.modal>
    </div>
    """
  end

  defp admin?(current_user, organization) do
    Enum.any?(organization.organization_users, fn organization_user ->
      organization_user.user_id == current_user.id and organization_user.role == "admin"
    end)
  end

  defp repository_label(%{repository: "", repository_owner: owner}),
    do: "Any repository owned by #{owner}"

  defp repository_label(%{repository: repository}), do: repository

  defp role_variant("write"), do: "purple"
  defp role_variant(_role), do: "blue"

  defp workflow_label(""), do: "Any"
  defp workflow_label(workflow), do: workflow

  defp environment_label(environment) when environment in [nil, ""], do: "Any"
  defp environment_label(environment), do: environment

  defp private_label(nil), do: "all packages"
  defp private_label(packages), do: Enum.join(packages, ", ")

  defp public_label(nil), do: "all owned packages"
  defp public_label(packages), do: Enum.join(packages, ", ")

  defp checked?(value), do: Phoenix.HTML.Form.normalize_value("checkbox", value)

  # The submitted names, so a list hidden behind an unchecked box or the read
  # role keeps what was typed.
  defp names_value(form, field) do
    key = Atom.to_string(field)

    case form.params do
      %{^key => names} -> join_names(names)
      _params -> join_names(form[field].value)
    end
  end

  defp join_names(names) when is_list(names), do: Enum.join(names, ", ")
  defp join_names(names), do: names
end
