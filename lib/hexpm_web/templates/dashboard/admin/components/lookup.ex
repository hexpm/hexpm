defmodule HexpmWeb.Dashboard.Admin.Components.Lookup do
  @moduledoc """
  What the admin pages show about a user, package or organization, from
  `Hexpm.AdminTasks.lookup_user/1`, `lookup_package/2` and
  `lookup_organization/1`, and the admin audit log table.
  """
  use Phoenix.Component
  use HexpmWeb, :verified_routes

  import HexpmWeb.Components.Table, only: [table: 1]
  import HexpmWeb.ViewHelpers, only: [pretty_datetime: 1]

  alias Hexpm.Accounts.User

  @link "text-primary-600 dark:text-primary-400 hover:underline"

  attr :lookup, :map, required: true

  def user_summary(assigns) do
    assigns = assign(assigns, :link, @link)

    ~H"""
    <.facts>
      <:fact label="Username">{@lookup.user.username}</:fact>
      <:fact :if={@lookup.user.full_name} label="Full name">{@lookup.user.full_name}</:fact>
      <:fact label="Role">{@lookup.user.role}</:fact>
      <:fact label="Joined">{pretty_datetime(@lookup.user.inserted_at)}</:fact>
      <:fact label="Two-factor authentication">
        {if User.tfa_enabled?(@lookup.user), do: "on", else: "off"}
      </:fact>
    </.facts>

    <.heading>Emails</.heading>
    <.none :if={@lookup.user.emails == []}>No emails.</.none>
    <.table :if={@lookup.user.emails != []}>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">Email</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Verified</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Primary</th>
      </:header>
      <:row>
        <tr :for={email <- Enum.sort_by(@lookup.user.emails, & &1.email)}>
          <td class="px-0 py-2 text-sm font-mono break-all">{email.email}</td>
          <td class="px-4 py-2 text-sm">{yes_no(email.verified)}</td>
          <td class="px-4 py-2 text-sm">{yes_no(email.primary)}</td>
        </tr>
      </:row>
    </.table>

    <.heading>Packages</.heading>
    <.none :if={@lookup.packages == []}>Owns no packages.</.none>
    <.table :if={@lookup.packages != []}>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">Package</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Level</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Owners</th>
      </:header>
      <:row>
        <tr :for={package <- @lookup.packages}>
          <td class="px-0 py-2 text-sm font-mono">
            <a href={package_path(package.repository, package.name)} class={@link}>
              {package_label(package.repository, package.name)}
            </a>
          </td>
          <td class="px-4 py-2 text-sm">{package.level}</td>
          <td class="px-4 py-2 text-sm">
            {if package.owner_count == 1, do: "only this user", else: package.owner_count}
          </td>
        </tr>
      </:row>
    </.table>

    <.heading>Organizations</.heading>
    <.none :if={@lookup.organizations == []}>Member of no organization.</.none>
    <.table :if={@lookup.organizations != []}>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">Organization</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Role</th>
      </:header>
      <:row>
        <tr :for={organization <- @lookup.organizations}>
          <td class="px-0 py-2 text-sm font-mono">
            <a href={~p"/dashboard/admin/organizations/#{organization.name}"} class={@link}>
              {organization.name}
            </a>
          </td>
          <td class="px-4 py-2 text-sm">{organization.role}</td>
        </tr>
      </:row>
    </.table>
    """
  end

  attr :lookup, :map, required: true
  attr :releases, :integer, default: 10, doc: "how many of the newest releases to list"

  def package_summary(assigns) do
    assigns =
      assigns
      |> assign(:link, @link)
      |> assign(:shown, Enum.take(assigns.lookup.releases, assigns.releases))

    ~H"""
    <.facts>
      <:fact label="Package">
        {package_label(@lookup.package.repository.name, @lookup.package.name)}
      </:fact>
      <:fact label="Created">{pretty_datetime(@lookup.package.inserted_at)}</:fact>
      <:fact label="Releases">{length(@lookup.releases)}</:fact>
      <:fact :if={@lookup.package.repository.name == "hexpm"} label="HexDocs search">
        {if @lookup.package.search_disabled_at,
          do: "disabled #{pretty_datetime(@lookup.package.search_disabled_at)}",
          else: "enabled"}
      </:fact>
    </.facts>

    <.heading>Owners</.heading>
    <.none :if={@lookup.owners == [] and @lookup.package.repository.name == "hexpm"}>
      No owners.
    </.none>
    <.none :if={@lookup.owners == [] and @lookup.package.repository.name != "hexpm"}>
      The members of
      <a href={~p"/dashboard/admin/organizations/#{@lookup.package.repository.name}"} class={@link}>
        {@lookup.package.repository.name}
      </a>
      have access.
    </.none>
    <.table :if={@lookup.owners != []}>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">Owner</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Level</th>
      </:header>
      <:row>
        <tr :for={owner <- @lookup.owners}>
          <td class="px-0 py-2 text-sm font-mono">
            <a href={~p"/dashboard/admin/users/#{owner.username}"} class={@link}>
              {owner.username}
            </a>
          </td>
          <td class="px-4 py-2 text-sm">{owner.level}</td>
        </tr>
      </:row>
    </.table>

    <.heading>Releases</.heading>
    <.none :if={@lookup.releases == []}>No releases.</.none>
    <.table :if={@shown != []}>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">Version</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Published</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Retired</th>
      </:header>
      <:row>
        <tr :for={release <- @shown}>
          <td class="px-0 py-2 text-sm font-mono">{release.version}</td>
          <td class="px-4 py-2 text-sm">{pretty_datetime(release.inserted_at)}</td>
          <td class="px-4 py-2 text-sm">{yes_no(release.retired)}</td>
        </tr>
      </:row>
    </.table>
    <.none :if={length(@lookup.releases) > length(@shown)}>
      And {length(@lookup.releases) - length(@shown)} older releases.
    </.none>
    """
  end

  attr :lookup, :map, required: true

  def organization_summary(assigns) do
    assigns = assign(assigns, :link, @link)

    ~H"""
    <.facts>
      <:fact label="Organization">{@lookup.organization.name}</:fact>
      <:fact
        :if={@lookup.repository && @lookup.repository != @lookup.organization.name}
        label="Repository"
      >
        {@lookup.repository}
      </:fact>
      <:fact label="Created">{pretty_datetime(@lookup.organization.inserted_at)}</:fact>
      <:fact label="Billing">{@lookup.billing_status || "no subscription"}</:fact>
      <:fact label="Two-factor authentication">
        {if @lookup.organization.tfa_required_at, do: "required", else: "not required"}
      </:fact>
    </.facts>

    <.heading>Members</.heading>
    <.none :if={@lookup.members == []}>No members.</.none>
    <.table :if={@lookup.members != []}>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">Member</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Role</th>
      </:header>
      <:row>
        <tr :for={member <- @lookup.members}>
          <td class="px-0 py-2 text-sm font-mono">
            <a href={~p"/dashboard/admin/users/#{member.username}"} class={@link}>
              {member.username}
            </a>
          </td>
          <td class="px-4 py-2 text-sm">{member.role}</td>
        </tr>
      </:row>
    </.table>

    <.heading>Packages</.heading>
    <.none :if={@lookup.packages == []}>No packages.</.none>
    <ul :if={@lookup.packages != []} class="flex flex-wrap gap-x-4 gap-y-1 text-sm font-mono">
      <li :for={package <- @lookup.packages}>
        <a href={package_path(@lookup.repository, package)} class={@link}>{package}</a>
      </li>
    </ul>
    """
  end

  attr :audit_logs, :list, required: true

  def audit_table(assigns) do
    ~H"""
    <.table>
      <:header>
        <th class="px-0 py-3 text-left text-sm font-medium">When</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Who</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Task</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Arguments</th>
        <th class="px-4 py-3 text-left text-sm font-medium">Outcome</th>
      </:header>
      <:row>
        <tr :for={log <- @audit_logs} class="align-top">
          <td class="px-0 py-3 text-sm whitespace-nowrap">
            {pretty_datetime(log.inserted_at)}
          </td>
          <td class="px-4 py-3 text-sm">
            <div>{actor(log)}</div>
            <div :if={log.remote_ip} class="text-grey-500 dark:text-grey-400 text-xs">
              {log.remote_ip}
            </div>
          </td>
          <td class="px-4 py-3 text-sm font-mono">{log.action}</td>
          <td class="px-4 py-3 text-sm">
            <dl class="grid grid-cols-[max-content_1fr] gap-x-3">
              <%= for {key, value} <- Enum.sort(log.params), not is_nil(value) do %>
                <dt class="text-grey-500 dark:text-grey-400">{key}</dt>
                <dd class="font-mono break-words">{format_param(value)}</dd>
              <% end %>
            </dl>
          </td>
          <td class="px-4 py-3 text-sm">
            <div class={["font-medium", status_class(log.status)]}>{log.status}</div>
            <div :if={log.result} class="font-mono text-xs break-words">{log.result}</div>
          </td>
        </tr>
      </:row>
    </.table>
    """
  end

  slot :fact do
    attr :label, :string, required: true
  end

  defp facts(assigns) do
    ~H"""
    <dl class="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-1 text-sm">
      <%= for fact <- @fact do %>
        <dt class="text-grey-600 dark:text-grey-300">{fact.label}</dt>
        <dd class="text-grey-900 dark:text-grey-100">{render_slot(fact)}</dd>
      <% end %>
    </dl>
    """
  end

  slot :inner_block, required: true

  defp heading(assigns) do
    ~H"""
    <h3 class="text-grey-900 dark:text-grey-100 font-medium mt-6 mb-2">
      {render_slot(@inner_block)}
    </h3>
    """
  end

  slot :inner_block, required: true

  defp none(assigns) do
    ~H"""
    <p class="text-grey-600 dark:text-grey-300 text-sm">{render_slot(@inner_block)}</p>
    """
  end

  defp package_path(repository, name), do: ~p"/dashboard/admin/packages/#{repository}/#{name}"

  defp package_label("hexpm", name), do: name
  defp package_label(repository, name), do: "#{repository}/#{name}"

  defp yes_no(true), do: "yes"
  defp yes_no(_false), do: "no"

  defp actor(%{user_data: %{"username" => username}}), do: username
  defp actor(%{user_agent: user_agent}), do: user_agent

  defp format_param(value) when is_binary(value), do: value
  defp format_param(value), do: inspect(value)

  defp status_class("ok"), do: "text-green-700 dark:text-green-400"
  defp status_class(_status), do: "text-red-700 dark:text-red-400"
end
