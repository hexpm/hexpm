defmodule HexpmWeb.PackageOwnerLive.AddOwner do
  use HexpmWeb, :live_view

  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  alias Hexpm.Repo
  alias HexpmWeb.RepositoryAccess

  on_mount {HexpmWeb.Live.InitAssigns, :default}

  @impl true
  def mount(_params, session, socket) do
    package =
      Repo.get(Package, Map.fetch!(session, "package_id"))
      |> Repo.preload(repository: :organization)

    socket =
      socket
      |> assign(:package, package)
      |> assign(:username, "")
      |> assign(:level, "maintainer")
      |> assign(:transfer, false)
      |> assign(:looked_up_user, nil)
      |> assign(:transfer_to, nil)

    {:ok, assign(socket, :manage?, manage?(socket)), layout: false}
  end

  # The socket outlives the page that authorized it, and the user is resolved
  # again before every event, so access is checked again before each lookup.
  @impl true
  def handle_event("lookup", params, socket) do
    if manage?(socket) do
      {:noreply, lookup(socket, params)}
    else
      {:noreply, assign(socket, manage?: false, transfer_to: nil)}
    end
  end

  defp lookup(socket, params) do
    username = String.trim(params["username"] || "")
    level = params["level"] || socket.assigns.level
    transfer = params["transfer"] == "true"

    looked_up =
      cond do
        username == "" ->
          nil

        username == socket.assigns.username and socket.assigns.looked_up_user != nil ->
          socket.assigns.looked_up_user

        true ->
          case Users.get_by_username(username, [:emails, :organization]) do
            nil ->
              :not_found

            %User{organization_id: nil} = user ->
              if User.verified_primary_email?(user), do: user, else: :unverified

            user ->
              if socket.assigns.package.repository_id == 1, do: user, else: :organization
          end
      end

    # Organizations can only be added by a transfer.
    transfer_to =
      case looked_up do
        %User{organization_id: nil} = user when transfer -> user
        %User{organization_id: nil} -> nil
        %User{} = organization -> organization
        _not_found -> nil
      end

    socket
    |> assign(:username, username)
    |> assign(:level, level)
    |> assign(:transfer, transfer)
    |> assign(:looked_up_user, looked_up)
    |> assign_transfer(transfer_to)
  end

  defp manage?(%{assigns: %{current_user: nil}}), do: false

  defp manage?(socket),
    do: RepositoryAccess.package_settings(socket, socket.assigns.package) == {:ok, :manage}

  defp assign_transfer(socket, nil), do: assign(socket, :transfer_to, nil)

  defp assign_transfer(socket, transfer_to) do
    package = socket.assigns.package

    assign(socket,
      transfer_to: transfer_to,
      removed_owners: Enum.reject(Owners.all(package, :user), &(&1.user_id == transfer_to.id)),
      workload_identities: Owners.workload_identities(package),
      stopped_workload_identities:
        Enum.reject(
          Owners.organization_workload_identities(package),
          &(&1.organization_id == transfer_to.organization_id)
        )
    )
  end

  @impl true
  def render(%{manage?: false} = assigns) do
    ~H"""
    <p class="text-sm text-grey-600 dark:text-grey-300">
      You can no longer change the owners of {@package.name}.
    </p>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <.button variant="primary" phx-click={show_modal("add-owner-modal")}>
        {icon(:heroicon, "plus", class: "w-4 h-4")} Add owner
      </.button>

      <.modal id="add-owner-modal" title="Add owner" max_width="md">
        <.sudo_form
          current_user={@current_user}
          action={ViewHelpers.path_for_owners(@package)}
          method="post"
          id="add-owner-form"
          phx-change="lookup"
        >
          <div class="space-y-4">
            <div>
              <label
                for="add-owner-username"
                class="block text-small font-medium text-grey-900 dark:text-grey-100 mb-[6px]"
              >
                Username
              </label>
              <input
                type="text"
                id="add-owner-username"
                name="username"
                value={@username}
                placeholder="Hex username"
                autocomplete="off"
                phx-debounce="300"
                required
                class="w-full h-10 text-sm bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg px-3 text-grey-800 dark:text-white placeholder:text-grey-400 focus:outline-none focus:ring-2 focus:ring-primary-500"
              />
            </div>

            <div>
              <label
                for="add-owner-level"
                class="block text-small font-medium text-grey-900 dark:text-grey-100 mb-[6px]"
              >
                Role
              </label>
              <div class="relative">
                <select
                  id="add-owner-level"
                  name="level"
                  disabled={@transfer_to != nil}
                  class="w-full h-10 text-sm bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg pl-3 pr-8 text-grey-800 dark:text-white cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-primary-500 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  <option
                    value="maintainer"
                    selected={@level == "maintainer" and is_nil(@transfer_to)}
                  >
                    Maintainer
                  </option>
                  <option value="full" selected={@level == "full" or @transfer_to != nil}>
                    Full owner
                  </option>
                </select>
                <div class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
                  {icon(:heroicon, "chevron-down", width: 15, height: 15)}
                </div>
              </div>
            </div>

            <label class="flex items-start gap-3 cursor-pointer has-[:disabled]:cursor-not-allowed">
              <input
                type="checkbox"
                id="add-owner-transfer-checkbox"
                name="transfer"
                value="true"
                checked={@transfer or organization?(@looked_up_user)}
                disabled={organization?(@looked_up_user)}
                class="mt-0.5 w-4 h-4 text-purple-600 border-grey-300 dark:border-grey-600 rounded focus:ring-2 focus:ring-purple-500"
              />
              <span class="flex flex-col gap-0.5">
                <span class="text-small font-medium text-grey-900 dark:text-grey-100">
                  Transfer ownership
                </span>
                <span class="text-xs text-grey-500 dark:text-grey-300">
                  Make the new owner the only owner of {@package.name}.
                </span>
              </span>
            </label>

            <div class="border border-grey-200 dark:border-grey-600 rounded-lg p-4 min-h-[88px] flex items-center bg-grey-50 dark:bg-grey-700/40">
              {render_preview(assigns)}
            </div>

            <%= if @transfer_to do %>
              <input type="hidden" name="transfer_to" value={@transfer_to.username} />
              {render_transfer(assigns)}
            <% end %>
          </div>

          <div class="flex justify-end gap-3 mt-6">
            <.button type="button" variant="secondary" phx-click={hide_modal("add-owner-modal")}>
              Cancel
            </.button>
            <.button
              type="submit"
              variant={if @transfer_to, do: "danger", else: "primary"}
              disabled={not match?(%User{}, @looked_up_user)}
            >
              {if @transfer_to, do: "Transfer to #{@transfer_to.username}", else: "Add as owner"}
            </.button>
          </div>
        </.sudo_form>
      </.modal>
    </div>
    """
  end

  defp render_preview(%{username: ""} = assigns) do
    ~H"""
    <p class="text-sm text-grey-500 dark:text-grey-300">
      Enter a Hex username to preview the user before adding.
    </p>
    """
  end

  defp render_preview(%{looked_up_user: :not_found} = assigns) do
    ~H"""
    <p class="text-sm text-red-600 dark:text-red-400">
      No user found with username <span class="font-medium">"{@username}"</span>.
    </p>
    """
  end

  defp render_preview(%{looked_up_user: :unverified} = assigns) do
    ~H"""
    <p class="text-sm text-red-600 dark:text-red-400">
      <span class="font-medium">{@username}</span>
      has not verified their primary email and cannot be added as an owner.
    </p>
    """
  end

  defp render_preview(%{looked_up_user: :organization} = assigns) do
    ~H"""
    <p class="text-sm text-red-600 dark:text-red-400">
      <span class="font-medium">{@username}</span>
      is an organization. Organizations can only own public packages.
    </p>
    """
  end

  defp render_preview(%{looked_up_user: nil} = assigns) do
    ~H"""
    <p class="text-sm text-grey-500 dark:text-grey-300">Looking up user…</p>
    """
  end

  defp render_preview(%{looked_up_user: %User{}} = assigns) do
    ~H"""
    <a
      href={HexpmWeb.Router.user_path(@looked_up_user)}
      target="_blank"
      rel="noopener"
      class="flex items-center gap-3 w-full group"
    >
      <img
        src={ViewHelpers.gravatar_url(User.email(@looked_up_user, :gravatar), :small)}
        alt={@looked_up_user.username}
        class="w-12 h-12 rounded-full flex-shrink-0"
      />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-grey-900 dark:text-white truncate group-hover:text-purple-600 dark:group-hover:text-primary-300 transition-colors">
          {@looked_up_user.username}
        </p>
        <p
          :if={@looked_up_user.full_name not in [nil, ""]}
          class="text-xs text-grey-600 dark:text-grey-300 truncate"
        >
          {@looked_up_user.full_name}
        </p>
        <p
          :if={User.email(@looked_up_user, :public)}
          class="text-xs text-grey-500 dark:text-grey-400 truncate"
        >
          {User.email(@looked_up_user, :public)}
        </p>
      </div>
    </a>
    """
  end

  defp render_transfer(assigns) do
    ~H"""
    <div
      id="add-owner-transfer"
      class="rounded-lg border border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-900/30 p-4 space-y-2 text-sm text-amber-900 dark:text-amber-100"
    >
      <p>
        {if User.organization?(@transfer_to),
          do: "Adding an organization transfers the package to it. "}{@transfer_to.username} becomes the only owner of {@package.name}.
      </p>
      <%= if @removed_owners != [] do %>
        <p>The transfer removes these owners:</p>
        <ul class="list-disc pl-5">
          <li :for={owner <- @removed_owners}>
            {owner.user.username}{if owner.user_id == @current_user.id, do: " (you)"}
          </li>
        </ul>
      <% end %>
      <%= if @workload_identities != [] do %>
        <p>The transfer removes these workload identities of {@package.name}:</p>
        <ul class="list-disc pl-5">
          <li :for={workload_identity <- @workload_identities}>
            {ViewHelpers.workload_identity_repositories(workload_identity)} ({workload_identity.workflow})
          </li>
        </ul>
      <% end %>
      <%= if @stopped_workload_identities != [] do %>
        <p>These organization workload identities stop publishing {@package.name}:</p>
        <ul class="list-disc pl-5">
          <li :for={workload_identity <- @stopped_workload_identities}>
            {workload_identity.organization.name}: {ViewHelpers.workload_identity_repositories(
              workload_identity
            )} ({workload_identity.workflow})
          </li>
        </ul>
      <% end %>
    </div>
    """
  end

  defp organization?(%User{} = user), do: User.organization?(user)
  defp organization?(_looked_up_user), do: false
end
