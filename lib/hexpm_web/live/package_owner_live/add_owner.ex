defmodule HexpmWeb.PackageOwnerLive.AddOwner do
  use HexpmWeb, :live_view

  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  alias Hexpm.Repo

  @impl true
  def mount(_params, session, socket) do
    package =
      Repo.get(Package, Map.fetch!(session, "package_id"))
      |> Repo.preload(:repository)

    current_user = Users.get_by_id(Map.fetch!(session, "current_user_id"), [:emails])

    socket =
      socket
      |> assign(:package, package)
      |> assign(:current_user, current_user)
      |> assign(:username, "")
      |> assign(:level, "maintainer")
      |> assign(:looked_up_user, nil)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("lookup", params, socket) do
    username = String.trim(params["username"] || "")
    level = params["level"] || "maintainer"

    looked_up =
      cond do
        username == "" ->
          nil

        username == socket.assigns.username and socket.assigns.looked_up_user != nil ->
          socket.assigns.looked_up_user

        true ->
          case Users.get_by_username(username, [:emails, :organization]) do
            nil -> :not_found
            user -> user
          end
      end

    {:noreply,
     socket
     |> assign(:username, username)
     |> assign(:level, level)
     |> assign(:looked_up_user, looked_up)}
  end

  @impl true
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
                  class="w-full h-10 text-sm bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg pl-3 pr-8 text-grey-800 dark:text-white cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="maintainer" selected={@level == "maintainer"}>Maintainer</option>
                  <option value="full" selected={@level == "full"}>Full owner</option>
                </select>
                <div class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
                  {icon(:heroicon, "chevron-down", width: 15, height: 15)}
                </div>
              </div>
            </div>

            <div class="border border-grey-200 dark:border-grey-600 rounded-lg p-4 min-h-[88px] flex items-center bg-grey-50 dark:bg-grey-700/40">
              {render_preview(assigns)}
            </div>
          </div>

          <div class="flex justify-end gap-3 mt-6">
            <.button type="button" variant="secondary" phx-click={hide_modal("add-owner-modal")}>
              Cancel
            </.button>
            <.button
              type="submit"
              variant="primary"
              disabled={not match?(%User{}, @looked_up_user)}
            >
              Add as owner
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

  defp render_preview(%{looked_up_user: nil} = assigns) do
    ~H"""
    <p class="text-sm text-grey-500 dark:text-grey-300">Looking up user…</p>
    """
  end

  defp render_preview(%{looked_up_user: %User{}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 w-full">
      <img
        src={ViewHelpers.gravatar_url(User.email(@looked_up_user, :gravatar), :small)}
        alt={@looked_up_user.username}
        class="w-12 h-12 rounded-full flex-shrink-0"
      />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-grey-900 dark:text-white truncate">
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
    </div>
    """
  end
end
