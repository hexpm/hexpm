defmodule HexpmWeb.Dashboard.Organization.Components.TrustedPublishersTab do
  @moduledoc """
  Trusted publishers tab content for the organization dashboard. Lists the
  GitHub Actions workflows that can fetch from the organization's repository,
  and publish to it with the write role. Admins add and remove them.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Badge, only: [badge: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1, icon_button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1, select_input: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]

  alias Hexpm.TrustedPublishers.TrustedPublisher

  attr :changeset, :any, required: true
  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :trusted_publishers, :list, required: true

  def trusted_publishers_tab(assigns) do
    assigns =
      assigns
      |> assign(:admin?, admin?(assigns.current_user, assigns.organization))
      |> assign(:form, to_form(assigns.changeset, as: :trusted_publisher))

    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">Trusted publishers</h2>
          <p class="text-grey-500 dark:text-grey-300 text-sm mt-1">
            GitHub Actions workflows that fetch packages from the {@organization.name} repository without an API key. With the write role they also publish and create packages in it.
            <a
              href={~p"/docs/trusted-publishers" <> "#organization-publishers"}
              class="text-primary-600 dark:text-primary-300 hover:underline"
            >
              Learn more
            </a>
          </p>
        </div>

        <ul class="divide-y divide-grey-100 dark:divide-grey-700">
          <li
            :for={trusted_publisher <- @trusted_publishers}
            id={"trusted-publisher-#{trusted_publisher.id}"}
            class="flex items-center justify-between gap-3 px-6 py-4"
          >
            <div class="min-w-0 space-y-1">
              <p class="flex flex-wrap items-center gap-2 text-sm font-medium text-grey-900 dark:text-white">
                <span class="break-all">{repository_label(trusted_publisher)}</span>
                <.badge variant={role_variant(trusted_publisher.role)}>
                  {trusted_publisher.role}
                </.badge>
              </p>
              <p class="text-xs text-grey-500 dark:text-grey-300">
                Workflow: {workflow_label(trusted_publisher.workflow)}
                <span aria-hidden="true">&middot;</span>
                Environment: {environment_label(trusted_publisher.environment)}
              </p>
              <p
                :if={trusted_publisher.role == "write"}
                class="text-xs text-grey-500 dark:text-grey-300"
              >
                Packages: {packages_label(trusted_publisher.packages)}
              </p>
            </div>

            <.icon_button
              :if={@admin?}
              icon="x-mark"
              variant="danger"
              aria-label={"Remove trusted publisher #{repository_label(trusted_publisher)}"}
              phx-click={show_modal("remove-trusted-publisher-#{trusted_publisher.id}")}
            />
          </li>
          <li
            :if={@trusted_publishers == []}
            class="px-6 py-4 text-sm text-grey-500 dark:text-grey-300"
          >
            No trusted publishers configured for this organization.
          </li>
        </ul>

        <p
          :if={not @admin?}
          class="px-6 py-3 border-t border-grey-200 dark:border-grey-700 bg-grey-50 dark:bg-grey-900 text-sm text-grey-600 dark:text-grey-300"
        >
          Only organization admins can add and remove trusted publishers.
        </p>
      </div>

      <div
        :if={@admin?}
        class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden"
      >
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">
            Add trusted publisher
          </h2>
        </div>

        <.sudo_form
          current_user={@current_user}
          action={~p"/dashboard/orgs/#{@organization}/trusted-publishers"}
          method="post"
          id="add-trusted-publisher-form"
          class="group/trusted-publisher px-6 py-5 flex flex-col gap-4"
        >
          <input type="hidden" name="trusted_publisher[provider]" value="github" />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.text_input
              field={@form[:repository_owner]}
              label="Repository owner"
              placeholder="acme"
              required
            />
            <.text_input
              field={@form[:repository]}
              value={TrustedPublisher.repository_name(@form[:repository].value)}
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

          <div class="hidden group-has-[option[value=write]:checked]/trusted-publisher:block">
            <.text_input
              field={@form[:packages]}
              value={packages_value(@form[:packages].value)}
              label="Packages"
              placeholder="All packages"
            />
            <p class="mt-1 text-xs text-grey-500 dark:text-grey-300">
              Package names separated by commas. A name can be a package that doesn't exist yet, which the workflow can then create. Leave empty to cover every package in the repository.
            </p>
          </div>

          <div class="flex flex-col gap-2 text-xs text-grey-500 dark:text-grey-300">
            <p>
              The write role needs a repository name and a workflow. With the read role, an empty workflow matches every workflow in the repository, and an empty repository name matches every repository the owner has, for example so all of them can fetch private dependencies.
            </p>
            <p>
              Anyone who can push a workflow file to a matching repository can then fetch, the same as with an organization key stored as a GitHub secret. Set an environment with protection rules to narrow a single repository.
            </p>
            <p>
              The repository ID is required for private GitHub repositories Hex can't see. Find it with <code class="text-xs">gh api repos/OWNER/NAME --jq .id</code>.
            </p>
          </div>

          <div class="flex justify-end">
            <.button type="submit" variant="primary">Add trusted publisher</.button>
          </div>
        </.sudo_form>
      </div>

      <.modal
        :for={trusted_publisher <- @trusted_publishers}
        :if={@admin?}
        id={"remove-trusted-publisher-#{trusted_publisher.id}"}
        title="Remove trusted publisher?"
        max_width="md"
      >
        <p class="text-sm text-grey-600 dark:text-grey-300">
          Workflows in
          <strong class="font-semibold text-grey-900 dark:text-white">
            {repository_label(trusted_publisher)}
          </strong>
          that match this publisher can no longer get Hex tokens for {@organization.name}. Tokens they already have keep working at repo.hex.pm until they expire, at most 15 minutes.
        </p>

        <.sudo_form
          current_user={@current_user}
          action={~p"/dashboard/orgs/#{@organization}/trusted-publishers/#{trusted_publisher.id}"}
          method="delete"
          id={"remove-trusted-publisher-form-#{trusted_publisher.id}"}
          class="mt-6 flex justify-end gap-3"
        >
          <.button
            type="button"
            variant="secondary"
            phx-click={hide_modal("remove-trusted-publisher-#{trusted_publisher.id}")}
          >
            Cancel
          </.button>
          <.button type="submit" variant="danger">Remove trusted publisher</.button>
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

  defp packages_label(nil), do: "All"
  defp packages_label(packages), do: Enum.join(packages, ", ")

  defp packages_value(packages) when is_list(packages), do: Enum.join(packages, ", ")
  defp packages_value(packages), do: packages
end
