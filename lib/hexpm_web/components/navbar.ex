defmodule HexpmWeb.Components.Navbar do
  @moduledoc """
  Navbar component with mobile menu toggle using Phoenix JS commands.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import HexpmWeb.ViewIcons, only: [icon: 3]

  @doc """
  Renders the mobile search toggle button.
  """
  attr :class, :string, default: ""

  def mobile_search_toggle(assigns) do
    ~H"""
    <button
      type="button"
      class={"tw:text-grey-200 tw:p-0 tw:cursor-pointer " <> @class}
      phx-click={toggle_mobile_search()}
      aria-label="Search"
      aria-expanded="false"
      aria-controls="mobile-search-bar"
    >
      {icon(:heroicon, "magnifying-glass", width: 18, height: 18)}
    </button>
    """
  end

  defp toggle_mobile_search do
    JS.toggle(
      to: "#mobile-search-bar",
      in:
        {"tw:transition-all tw:ease-out tw:duration-200 tw:transform",
         "tw:opacity-0 tw:-translate-y-2", "tw:opacity-100 tw:translate-y-0"},
      out:
        {"tw:transition-all tw:ease-in tw:duration-150 tw:transform",
         "tw:opacity-100 tw:translate-y-0", "tw:opacity-0 tw:-translate-y-2"}
    )
    |> JS.focus(to: "#mobile-search-input")
  end

  @doc """
  Renders the mobile menu toggle button with animated open/close.
  """
  attr :class, :string, default: ""

  def mobile_menu_toggle(assigns) do
    ~H"""
    <button
      type="button"
      class={"tw:bg-grey-700 tw:rounded-lg tw:p-[10px] tw:w-10 tw:h-10 tw:flex tw:items-center tw:justify-center tw:cursor-pointer " <> @class}
      phx-click={toggle_mobile_menu()}
      aria-expanded="false"
      aria-controls="navbar-mobile"
    >
      <span class="tw:sr-only">Toggle navigation</span>
      <%!-- Hamburger icon (shown when closed) --%>
      <span id="menu-open-icon" class="tw:block">
        {icon(:heroicon, "bars-3", width: 20, height: 20, class: "tw:text-grey-200")}
      </span>
      <%!-- X icon (shown when open) --%>
      <span id="menu-close-icon" class="tw:hidden">
        {icon(:heroicon, "x-mark", width: 20, height: 20, class: "tw:text-grey-200")}
      </span>
    </button>
    """
  end

  defp toggle_mobile_menu do
    JS.toggle(
      to: "#navbar-mobile",
      in:
        {"tw:transition-all tw:ease-out tw:duration-300 tw:transform",
         "tw:opacity-0 tw:-translate-y-2", "tw:opacity-100 tw:translate-y-0"},
      out:
        {"tw:transition-all tw:ease-in tw:duration-200 tw:transform",
         "tw:opacity-100 tw:translate-y-0", "tw:opacity-0 tw:-translate-y-2"}
    )
    |> JS.toggle(to: "#menu-open-icon")
    |> JS.toggle(to: "#menu-close-icon")
  end

  @doc """
  Renders the complete user dropdown (button + menu + backdrop).
  """
  attr :avatar_url, :string, required: true
  attr :class, :string, default: ""
  attr :csrf_token, :string, required: true
  attr :dashboard_path, :string, required: true
  attr :logout_path, :string, required: true
  attr :user_path, :string, required: true
  attr :username, :string, required: true

  def user_dropdown(assigns) do
    ~H"""
    <div class="tw:relative">
      <%!-- Toggle Button --%>
      <button
        type="button"
        class={"tw:flex tw:items-center tw:gap-[10px] tw:bg-grey-600 tw:px-6 tw:py-[11px] tw:rounded-lg tw:text-white tw:text-md tw:leading-[18px] tw:cursor-pointer " <> @class}
        phx-click={toggle_user_dropdown()}
        aria-expanded="false"
        aria-haspopup="true"
        aria-controls="user-dropdown-menu"
      >
        <img src={@avatar_url} class="tw:w-5 tw:h-5 tw:rounded-full" alt={@username} />
        <span>{@username}</span>
        {icon(:heroicon, "chevron-down", width: 16, height: 16, class: "tw:text-grey-200")}
      </button>

      <%!-- Backdrop (invisible, for click-away) --%>
      <div
        id="user-dropdown-backdrop"
        class="tw:hidden tw:fixed tw:inset-0 tw:z-40"
        phx-click={hide_user_dropdown()}
      />

      <%!-- Dropdown Menu --%>
      <div
        id="user-dropdown-menu"
        class="tw:hidden tw:absolute tw:right-0 tw:mt-2 tw:w-48 tw:bg-grey-700 tw:border tw:border-grey-600 tw:rounded-lg tw:shadow-lg tw:py-1 tw:z-50"
      >
        <a
          href={@user_path}
          class="tw:block tw:px-4 tw:py-2 tw:text-sm tw:text-grey-200 tw:hover:bg-grey-600 tw:transition-colors"
        >
          Profile
        </a>
        <a
          href={@dashboard_path}
          class="tw:block tw:px-4 tw:py-2 tw:text-sm tw:text-grey-200 tw:hover:bg-grey-600 tw:transition-colors"
        >
          Dashboard
        </a>
        <div class="tw:border-t tw:border-grey-600 tw:my-1"></div>
        <form action={@logout_path} method="post">
          <input type="hidden" name="_csrf_token" value={@csrf_token} />
          <button
            type="submit"
            class="tw:w-full tw:text-left tw:px-4 tw:py-2 tw:text-sm tw:text-grey-200 tw:hover:bg-grey-600 tw:transition-colors tw:cursor-pointer"
          >
            Log out
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp toggle_user_dropdown do
    JS.toggle(
      to: "#user-dropdown-menu",
      in:
        {"tw:transition-all tw:ease-out tw:duration-200 tw:transform",
         "tw:opacity-0 tw:-translate-y-2", "tw:opacity-100 tw:translate-y-0"},
      out:
        {"tw:transition-all tw:ease-in tw:duration-150 tw:transform",
         "tw:opacity-100 tw:translate-y-0", "tw:opacity-0 tw:-translate-y-2"}
    )
    |> JS.toggle(to: "#user-dropdown-backdrop")
  end

  defp hide_user_dropdown do
    JS.hide(
      to: "#user-dropdown-menu",
      transition:
        {"tw:transition-all tw:ease-in tw:duration-150 tw:transform",
         "tw:opacity-100 tw:translate-y-0", "tw:opacity-0 tw:-translate-y-2"}
    )
    |> JS.hide(to: "#user-dropdown-backdrop")
  end
end
