defmodule HexpmWeb.Dashboard.Organization.Components.WorkloadIdentitiesTab do
  @moduledoc """
  Workload identities tab content for the organization dashboard. Lists the
  GitHub Actions workflows that can fetch from the organization's repository,
  and with the write role publish to it and publish the public packages the
  organization owns. Admins with 2FA on their account add, change and remove
  them.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Badge, only: [badge: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1, button_link: 1, icon_button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [errors: 1, field_errors: 2, text_input: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]
  import HexpmWeb.Components.Tooltip, only: [tooltip: 1]
  import HexpmWeb.Components.WorkloadIdentity, only: [repositories_input: 1, trusted_workflows: 1]

  alias Hexpm.Accounts.{Organization, User}

  attr :changeset, :any, required: true
  attr :current_user, :map, required: true
  attr :editing, :any, default: nil, doc: "The workload identity the form changes, if any"
  attr :organization, :map, required: true
  attr :unowned_public_packages, :map, default: %{}
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
            GitHub Actions workflows that fetch and publish {@organization.name}'s packages without an API key.
            <a
              href={~p"/docs/workload-identity" <> "#organization-workload-identities"}
              class="text-primary-600 dark:text-primary-300 hover:underline"
            >
              Learn more
            </a>
          </p>
        </div>

        <ul class="flex flex-col gap-3 p-4">
          <li
            :for={workload_identity <- @workload_identities}
            id={"workload-identity-#{workload_identity.id}"}
            class={[
              "rounded-lg border px-4 py-3 flex flex-col gap-3",
              if(@editing && @editing.id == workload_identity.id,
                do: "border-primary-400 dark:border-primary-500",
                else: "border-grey-200 dark:border-grey-700"
              )
            ]}
          >
            <div class="flex items-start justify-between gap-3">
              <p class="flex flex-wrap items-center gap-2 text-sm font-semibold text-grey-900 dark:text-white">
                {title(workload_identity)}
                <.badge variant={role_variant(workload_identity.role)}>
                  {String.capitalize(workload_identity.role)}
                </.badge>
              </p>

              <div :if={@admin?} class="flex shrink-0 items-center gap-2">
                <.button_link
                  :if={@tfa?}
                  href={~p"/dashboard/orgs/#{@organization}/workload-identities/#{workload_identity}/edit" <> "#workload-identity-form"}
                  variant="outline"
                  size="sm"
                >
                  Edit
                </.button_link>
                <.icon_button
                  :if={@tfa?}
                  icon="x-mark"
                  variant="danger"
                  aria-label={"Remove workload identity #{title(workload_identity)}"}
                  phx-click={show_modal("remove-workload-identity-#{workload_identity.id}")}
                />
                <.tooltip :if={not @tfa?} text="Requires 2FA">
                  <.icon_button
                    icon="x-mark"
                    variant="danger"
                    aria-label={"Remove workload identity #{title(workload_identity)}"}
                    disabled
                  />
                </.tooltip>
              </div>
            </div>

            <dl class="grid grid-cols-[3.5rem_1fr] gap-x-3 gap-y-2 text-sm">
              <dt class="text-grey-500 dark:text-grey-300">Can</dt>
              <dd>
                <ul class="list-disc pl-4 text-grey-900 dark:text-grey-100">
                  <li :for={line <- capabilities(workload_identity, @organization)}>{line}</li>
                  <li :if={workload_identity.role == "write" and workload_identity.covers_public}>
                    Publish public packages:
                    <.public_packages
                      workload_identity={workload_identity}
                      organization={@organization}
                      unowned={Map.get(@unowned_public_packages, workload_identity.id, [])}
                    />
                  </li>
                </ul>
              </dd>
              <dt class="text-grey-500 dark:text-grey-300">From</dt>
              <dd><.trusted_workflows workload_identity={workload_identity} /></dd>
            </dl>

            <.unowned_note
              organization={@organization}
              names={Map.get(@unowned_public_packages, workload_identity.id, [])}
            />

            <p class="text-xs text-grey-500 dark:text-grey-300">
              Added {Calendar.strftime(workload_identity.inserted_at, "%-d %b %Y")}
            </p>
          </li>
          <li
            :if={@workload_identities == []}
            class="px-2 py-1 text-sm text-grey-500 dark:text-grey-300"
          >
            No workload identities configured for this organization.
          </li>
        </ul>

        <p
          :if={not @admin?}
          class="px-6 py-3 border-t border-grey-200 dark:border-grey-700 bg-grey-50 dark:bg-grey-900 text-sm text-grey-600 dark:text-grey-300"
        >
          Only organization admins can add, change and remove workload identities.
        </p>
      </div>

      <div
        :if={@admin?}
        id="workload-identity-form"
        class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden"
      >
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">
            {if @editing, do: "Change workload identity", else: "Add workload identity"}
          </h2>
        </div>

        <div
          :if={not @tfa?}
          class="mx-6 mt-5 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 px-4 py-3"
        >
          <p class="text-sm text-amber-900 dark:text-amber-100">
            Two-factor authentication on your account is required to add, change or remove workload identities.
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
          action={form_action(@organization, @editing)}
          method={if @editing, do: "put", else: "post"}
          id="add-workload-identity-form"
          class="group/workload-identity px-6 py-5 flex flex-col gap-5"
        >
          <fieldset disabled={not @tfa?} class="flex flex-col gap-5 disabled:opacity-50">
            <input :if={!@editing} type="hidden" name="workload_identity[provider]" value="github" />
            <input
              :if={@editing}
              type="hidden"
              name="workload_identity[version]"
              value={@form.params["version"] || Hexpm.WorkloadIdentities.version(@editing)}
            />

            <div class="flex flex-col gap-2">
              <span class="text-small font-medium text-grey-900 dark:text-grey-100">Role</span>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <.role_option
                  form={@form}
                  value="read"
                  title="Read"
                  disabled={not @billing? or @editing != nil}
                >
                  Fetch every package in the {@organization.name} repository from repo.hex.pm.
                  <span :if={not @billing?}>Needs an active billing subscription.</span>
                </.role_option>
                <.role_option
                  form={@form}
                  value="write"
                  title="Write"
                  disabled={@editing != nil}
                >
                  Publish packages, the ones you pick below.
                </.role_option>
              </div>
              <p :if={@editing} class="text-xs text-grey-500 dark:text-grey-300">
                The role and the repository owner can't change. Add a new workload identity for a different one.
              </p>
              <.errors errors={field_errors(@form, :role)} />
            </div>

            <div class="flex flex-col gap-4">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-grey-500 dark:text-grey-300">
                GitHub workflows
              </h3>

              <.text_input
                :if={!@editing}
                field={@form[:repository_owner]}
                label="Repository owner"
                placeholder="acme"
                required
              />
              <p :if={@editing} class="text-sm text-grey-900 dark:text-grey-100">
                <span class="font-medium">Repository owner</span>
                <span class="ml-2 font-mono">{@editing.repository_owner}</span>
              </p>

              <.repositories_input form={@form}>
                <:help>
                  <span class="group-has-[#workload-identity-role-write:checked]/workload-identity:hidden">
                    One per line. Leave it empty to match every repository the owner has, and then leave the workflow and environment empty too.
                  </span>
                  <span class="hidden group-has-[#workload-identity-role-write:checked]/workload-identity:inline">
                    One per line, at least one.
                  </span>
                  Hex reads each repository's ID from GitHub. For a private repository Hex can't see, add its ID after the name, found with <code class="text-xs">gh api repos/OWNER/NAME --jq .id</code>.
                </:help>
              </.repositories_input>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <.text_input field={@form[:workflow]} label="Workflow" placeholder="release.yml" />
                  <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
                    <span class="group-has-[#workload-identity-role-write:checked]/workload-identity:hidden">
                      Optional. Empty matches every workflow in the repositories.
                    </span>
                    <span class="hidden group-has-[#workload-identity-role-write:checked]/workload-identity:inline">
                      The file name of the workflow that publishes.
                    </span>
                  </p>
                </div>
                <div>
                  <.text_input field={@form[:environment]} label="Environment" placeholder="release" />
                  <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
                    <span class="group-has-[#workload-identity-role-write:checked]/workload-identity:hidden">
                      Optional. Empty matches any environment or none.
                    </span>
                    <span class="hidden group-has-[#workload-identity-role-write:checked]/workload-identity:inline">
                      Required when a repository is public. Its protection rules are the check GitHub runs before a publish.
                    </span>
                  </p>
                </div>
              </div>
            </div>

            <p class="rounded-lg border border-dashed border-grey-200 dark:border-grey-700 px-4 py-3 text-sm text-grey-500 dark:text-grey-300 group-has-[#workload-identity-role-write:checked]/workload-identity:hidden">
              Read fetches every package in the {@organization.name} repository. Public packages need no credentials to fetch.
            </p>

            <div class="hidden group-has-[#workload-identity-role-write:checked]/workload-identity:flex flex-col gap-3">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-grey-500 dark:text-grey-300">
                Packages
              </h3>

              <div class="group/private rounded-lg border border-grey-200 dark:border-grey-700 p-4 flex flex-col gap-3">
                <label class={[
                  "flex items-start gap-3",
                  if(@billing?, do: "cursor-pointer", else: "cursor-not-allowed opacity-50")
                ]}>
                  <%!-- Without billing the box is disabled, and an edit keeps what's stored --%>
                  <input
                    type="hidden"
                    name="workload_identity[covers_private]"
                    value={
                      if @billing? or is_nil(@editing),
                        do: "false",
                        else: to_string(checked?(@form[:covers_private].value))
                    }
                  />
                  <input
                    type="checkbox"
                    id="workload_identity_covers_private"
                    name="workload_identity[covers_private]"
                    value="true"
                    checked={checked?(@form[:covers_private].value)}
                    disabled={not @billing?}
                    class="mt-0.5 w-4 h-4 text-purple-600 border-grey-300 dark:border-grey-600 rounded focus:ring-2 focus:ring-purple-500"
                  />
                  <span class="flex flex-col gap-0.5">
                    <span class="text-small font-medium text-grey-900 dark:text-grey-100">
                      Private packages in {@organization.name}
                    </span>
                    <span class="text-xs text-grey-500 dark:text-grey-300">
                      Publish and create packages in the {@organization.name} repository. Also fetches every package in it.
                      <span :if={not @billing?}>Needs an active billing subscription.</span>
                    </span>
                  </span>
                </label>
                <div class="hidden group-has-[:checked]/private:block">
                  <.text_input
                    field={@form[:packages]}
                    value={names_value(@form, :packages)}
                    label="Private package names"
                    placeholder="All packages in the repository"
                  />
                  <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
                    Separated by commas. A name can be a package that doesn't exist yet, which the workflow can then create. Leave it empty to cover every package in the repository.
                  </p>
                </div>
              </div>

              <div class="group/public rounded-lg border border-grey-200 dark:border-grey-700 p-4 flex flex-col gap-3">
                <label class="flex items-start gap-3 cursor-pointer">
                  <input type="hidden" name="workload_identity[covers_public]" value="false" />
                  <input
                    type="checkbox"
                    id="workload_identity_covers_public"
                    name="workload_identity[covers_public]"
                    value="true"
                    checked={checked?(@form[:covers_public].value)}
                    class="mt-0.5 w-4 h-4 text-purple-600 border-grey-300 dark:border-grey-600 rounded focus:ring-2 focus:ring-purple-500"
                  />
                  <span class="flex flex-col gap-0.5">
                    <span class="text-small font-medium text-grey-900 dark:text-grey-100">
                      Public packages {@organization.name} owns
                    </span>
                    <span class="text-xs text-grey-500 dark:text-grey-300">
                      Publish releases of public packages on hex.pm. Doesn't fetch or create packages.
                    </span>
                  </span>
                </label>
                <div class="hidden group-has-[:checked]/public:block">
                  <.text_input
                    field={@form[:public_packages]}
                    value={names_value(@form, :public_packages)}
                    label="Public package names"
                    placeholder={"All public packages #{@organization.name} owns"}
                  />
                  <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
                    Separated by commas. Leave it empty to cover every public package {@organization.name} owns, including packages it becomes an owner of later. Workload identities don't create public packages, so publish a package's first release with a user account or an API key. Each public release shows the GitHub repository, workflow and actor that published it, also when the repository is private.
                  </p>
                </div>
              </div>

              <.errors errors={field_errors(@form, :covers_private)} />
            </div>
          </fieldset>

          <div class="flex justify-end gap-3">
            <.button_link
              :if={@editing}
              href={~p"/dashboard/orgs/#{@organization}/workload-identities"}
              variant="secondary"
            >
              Cancel
            </.button_link>
            <.button :if={@tfa?} type="submit" variant="primary">
              {if @editing, do: "Save changes", else: "Add workload identity"}
            </.button>
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
            {HexpmWeb.ViewHelpers.workload_identity_repositories(workload_identity)}
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

  attr :form, :any, required: true
  attr :value, :string, required: true
  attr :title, :string, required: true
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp role_option(assigns) do
    ~H"""
    <label class={[
      "flex items-start gap-3 rounded-lg border p-3 has-[:checked]:border-primary-500 has-[:checked]:ring-1 has-[:checked]:ring-primary-500",
      "border-grey-200 dark:border-grey-700",
      if(@disabled, do: "cursor-not-allowed opacity-60", else: "cursor-pointer")
    ]}>
      <input
        type="radio"
        id={"workload-identity-role-#{@value}"}
        name="workload_identity[role]"
        value={@value}
        checked={@form[:role].value == @value}
        disabled={@disabled}
        class="mt-0.5 w-4 h-4 text-primary-600 border-grey-300 dark:border-grey-600 focus:ring-2 focus:ring-primary-500"
      />
      <span class="flex flex-col gap-0.5">
        <span class="text-sm font-semibold text-grey-900 dark:text-grey-100">{@title}</span>
        <span class="text-xs text-grey-500 dark:text-grey-300">{render_slot(@inner_block)}</span>
      </span>
    </label>
    """
  end

  attr :workload_identity, :map, required: true
  attr :organization, :map, required: true
  attr :unowned, :list, required: true

  defp public_packages(%{workload_identity: %{public_packages: nil}} = assigns) do
    ~H"""
    every public package {@organization.name} owns
    """
  end

  defp public_packages(assigns) do
    assigns = assign(assigns, :last, List.last(assigns.workload_identity.public_packages))

    ~H"""
    <span :for={name <- @workload_identity.public_packages}><s
      :if={name in @unowned}
      class="text-grey-400 dark:text-grey-500"
    >{name}</s><span :if={name not in @unowned}>{name}</span><span :if={name != @last}>, </span></span>
    """
  end

  attr :organization, :map, required: true
  attr :names, :list, required: true

  defp unowned_note(%{names: []} = assigns), do: ~H""

  defp unowned_note(assigns) do
    ~H"""
    <p class="rounded-md bg-amber-50 dark:bg-amber-900/20 px-3 py-2 text-xs text-amber-900 dark:text-amber-100">
      {@organization.name} doesn't own {Enum.join(@names, ", ")}, so this workload identity doesn't publish {them(
        @names
      )}.
    </p>
    """
  end

  defp them([_name]), do: "it"
  defp them(_names), do: "them"

  defp form_action(organization, nil), do: ~p"/dashboard/orgs/#{organization}/workload-identities"

  defp form_action(organization, editing),
    do: ~p"/dashboard/orgs/#{organization}/workload-identities/#{editing}"

  defp admin?(current_user, organization) do
    Enum.any?(organization.organization_users, fn organization_user ->
      organization_user.user_id == current_user.id and organization_user.role == "admin"
    end)
  end

  defp title(%{role: "read"}), do: "Fetch packages"

  defp title(%{covers_private: true, covers_public: true}),
    do: "Publish private and public packages"

  defp title(%{covers_private: true}), do: "Publish private packages"
  defp title(%{covers_public: true}), do: "Publish public packages"

  defp capabilities(%{role: "read"}, organization),
    do: ["Fetch every package in #{organization.name}"]

  defp capabilities(%{covers_private: true, packages: nil}, organization),
    do: ["Publish and create every package in #{organization.name}, and fetch them"]

  defp capabilities(%{covers_private: true, packages: packages}, organization) do
    [
      "Publish and create these packages in #{organization.name}: #{Enum.join(packages, ", ")}",
      "Fetch every package in #{organization.name}"
    ]
  end

  defp capabilities(_workload_identity, _organization), do: []

  defp role_variant("write"), do: "purple"
  defp role_variant(_role), do: "blue"

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
