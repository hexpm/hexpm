defmodule HexpmWeb.Components.Navbar do
  @moduledoc """
  Navbar component with mobile menu toggle using Phoenix JS commands.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.ViewHelpers, only: [gravatar_url: 2]
  import HexpmWeb.ViewIcons, only: [icon: 3]

  alias Hexpm.Accounts.User
  alias Phoenix.LiveView.JS

  @doc """
  Renders the main header/navbar.
  """
  attr :current_user, :any, default: nil
  attr :search, :string, default: nil
  attr :show_search, :boolean, default: true

  def header(assigns) do
    ~H"""
    <nav id="main-navbar" class="tw:bg-grey-900 tw:w-full tw:font-sans">
      <div class="tw:max-w-7xl tw:mx-auto tw:px-4 tw:lg:px-0">
        <div class="tw:flex tw:items-center tw:justify-between tw:h-[72px] tw:gap-8 tw:lg:gap-20">
          <.logo />
          <.desktop_nav current_user={@current_user} search={@search} show_search={@show_search} />
          <.mobile_nav_controls current_user={@current_user} show_search={@show_search} />
        </div>

        <.mobile_search_bar :if={@show_search} search={@search} />
        <.mobile_menu current_user={@current_user} />
      </div>
    </nav>
    """
  end

  defp logo(assigns) do
    ~H"""
    <a href="/" class="tw:shrink-0 tw:flex tw:items-center tw:gap-3">
      <img src={~p"/images/hex-full.svg"} alt="hex logo" class="tw:h-8 tw:w-auto" />
      <span class="tw:text-white tw:text-2xl tw:font-bold tw:tracking-tight">
        Hex
      </span>
    </a>
    """
  end

  attr :current_user, :any, required: true
  attr :search, :string, required: true
  attr :show_search, :boolean, required: true

  defp desktop_nav(assigns) do
    ~H"""
    <div class="tw:hidden tw:lg:flex tw:items-center tw:flex-1 tw:justify-end tw:gap-10">
      <.search_form :if={@show_search} search={@search} />
      <.nav_links />
      <.auth_section current_user={@current_user} />
    </div>
    """
  end

  defp nav_links(assigns) do
    ~H"""
    <a
      href={~p"/packages"}
      class="tw:text-grey-200 tw:text-md tw:hover:text-white tw:transition-colors"
    >
      Packages
    </a>
    <a
      href={~p"/pricing"}
      class="tw:text-grey-200 tw:text-md tw:hover:text-white tw:transition-colors"
    >
      Pricing
    </a>
    <a href={~p"/docs"} class="tw:text-grey-200 tw:text-md tw:hover:text-white tw:transition-colors">
      Docs
    </a>
    """
  end

  attr :current_user, :any, required: true

  defp auth_section(assigns) do
    ~H"""
    <div :if={@current_user}>
      <.user_dropdown
        avatar_url={gravatar_url(User.email(@current_user, :gravatar), :small)}
        csrf_token={Plug.CSRFProtection.get_csrf_token()}
        dashboard_path={~p"/dashboard/profile"}
        logout_path={~p"/logout"}
        user_path={~p"/users/#{@current_user}"}
        username={@current_user.username}
      />
    </div>
    <a
      :if={!@current_user}
      href={~p"/login"}
      class="tw:inline-flex tw:items-center tw:justify-center tw:bg-grey-400 tw:px-6 tw:py-1 tw:rounded-lg tw:text-white tw:text-md tw:hover:bg-grey-500 tw:hover:scale-105 tw:transition-all tw:duration-200"
    >
      Log In
    </a>
    """
  end

  attr :current_user, :any, required: true
  attr :show_search, :boolean, required: true

  defp mobile_nav_controls(assigns) do
    ~H"""
    <div class="tw:flex tw:lg:hidden tw:items-center tw:gap-6">
      <img
        :if={@current_user}
        src={gravatar_url(User.email(@current_user, :gravatar), :small)}
        class="tw:w-5 tw:h-5 tw:rounded-full"
        alt={@current_user.username}
      />
      <.mobile_search_toggle :if={@show_search} />
      <.mobile_menu_toggle />
    </div>
    """
  end

  attr :search, :string, required: true

  defp mobile_search_bar(assigns) do
    ~H"""
    <div id="mobile-search-bar" class="tw:hidden tw:lg:hidden! tw:bg-grey-900 tw:pb-4">
      <form role="search" action={~p"/packages"}>
        <div class="tw:relative">
          <div class="tw:absolute tw:left-3 tw:top-1/2 tw:-translate-y-1/2 tw:pointer-events-none">
            {icon(:heroicon, "magnifying-glass", width: 18, height: 18, class: "tw:text-grey-300")}
          </div>
          <input
            id="mobile-search-input"
            name="search"
            type="text"
            value={@search}
            placeholder="Find packages..."
            class="tw:w-full tw:bg-grey-800 tw:border tw:border-grey-600 tw:rounded-lg tw:px-3 tw:pl-10 tw:py-[11px] tw:text-white tw:text-base tw:font-medium tw:leading-4 tw:placeholder:text-grey-300 tw:focus:outline-none tw:focus:border-grey-500 tw:focus:shadow-[inset_0px_0px_6px_0px_rgba(255,255,255,0.3)]"
          />
          <input type="hidden" name="sort" value="recent_downloads" />
        </div>
      </form>
    </div>
    """
  end

  attr :current_user, :any, required: true

  defp mobile_menu(assigns) do
    ~H"""
    <div id="navbar-mobile" class="tw:hidden tw:lg:hidden! tw:bg-grey-900 tw:pb-6">
      <div class="tw:flex tw:flex-col tw:gap-4">
        <.mobile_nav_links />
        <.mobile_auth_section current_user={@current_user} />
      </div>
    </div>
    """
  end

  defp mobile_nav_links(assigns) do
    ~H"""
    <a href={~p"/packages"} class="tw:text-grey-200 tw:text-md tw:py-2 tw:hover:text-white">
      Packages
    </a>
    <a href={~p"/pricing"} class="tw:text-grey-200 tw:text-md tw:py-2 tw:hover:text-white">
      Pricing
    </a>
    <a href={~p"/docs"} class="tw:text-grey-200 tw:text-md tw:py-2 tw:hover:text-white">
      Docs
    </a>
    """
  end

  attr :current_user, :any, required: true

  defp mobile_auth_section(assigns) do
    ~H"""
    <div :if={@current_user} class="tw:border-t tw:border-grey-700 tw:pt-4 tw:mt-2">
      <.mobile_user_menu_link href={~p"/users/#{@current_user}"} label="Profile" />
      <.mobile_user_menu_link href={~p"/dashboard/profile"} label="Dashboard" />
      <.mobile_logout_form />
    </div>
    <a
      :if={!@current_user}
      href={~p"/login"}
      class="tw:bg-grey-600 tw:px-6 tw:py-[11px] tw:rounded-lg tw:text-white tw:text-md tw:text-center tw:hover:bg-grey-500 tw:mt-2"
    >
      Log In
    </a>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true

  defp mobile_user_menu_link(assigns) do
    ~H"""
    <a href={@href} class="tw:block tw:text-grey-200 tw:text-md tw:py-2 tw:hover:text-white">
      {@label}
    </a>
    """
  end

  defp mobile_logout_form(assigns) do
    ~H"""
    <form action={~p"/logout"} method="post" class="tw:mt-2">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <button
        type="submit"
        class="tw:w-full tw:text-left tw:text-grey-200 tw:text-md tw:py-2 tw:hover:text-white tw:cursor-pointer"
      >
        Log out
      </button>
    </form>
    """
  end

  attr :search, :string, default: nil

  defp search_form(assigns) do
    ~H"""
    <form role="search" action={~p"/packages"} class="tw:shrink-0 tw:w-[420px] tw:mr-auto">
      <div class="tw:relative tw:flex tw:items-center">
        <div class="tw:absolute tw:left-3 tw:pointer-events-none">
          {icon(:heroicon, "magnifying-glass", width: 18, height: 18, class: "tw:text-grey-300")}
        </div>
        <input
          placeholder="Find packages..."
          name="search"
          type="text"
          class="tw:w-full tw:h-[40px] tw:bg-grey-800 tw:border tw:border-grey-600 tw:rounded-lg tw:px-3 tw:pl-10 tw:py-[11px] tw:text-white tw:leading-4 tw:placeholder:text-grey-300 tw:focus:outline-none tw:focus:border-grey-500 tw:focus:shadow-[inset_0px_0px_6px_0px_rgba(255,255,255,0.3)]"
          value={@search}
        />
        <input type="hidden" name="sort" value="recent_downloads" />
      </div>
    </form>
    """
  end

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
      <.user_dropdown_button avatar_url={@avatar_url} class={@class} username={@username} />

      <%!-- Backdrop for click-away --%>
      <div
        id="user-dropdown-backdrop"
        class="tw:hidden tw:fixed tw:inset-0 tw:z-40"
        phx-click={hide_user_dropdown()}
      />

      <.user_dropdown_menu
        csrf_token={@csrf_token}
        dashboard_path={@dashboard_path}
        logout_path={@logout_path}
        user_path={@user_path}
      />
    </div>
    """
  end

  attr :avatar_url, :string, required: true
  attr :class, :string, required: true
  attr :username, :string, required: true

  defp user_dropdown_button(assigns) do
    ~H"""
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
    """
  end

  attr :csrf_token, :string, required: true
  attr :dashboard_path, :string, required: true
  attr :logout_path, :string, required: true
  attr :user_path, :string, required: true

  defp user_dropdown_menu(assigns) do
    ~H"""
    <div
      id="user-dropdown-menu"
      class="tw:hidden tw:absolute tw:right-0 tw:mt-2 tw:w-48 tw:bg-grey-700 tw:border tw:border-grey-600 tw:rounded-lg tw:shadow-lg tw:py-1 tw:z-50"
    >
      <.user_menu_link href={@user_path} label="Profile" />
      <.user_menu_link href={@dashboard_path} label="Dashboard" />
      <div class="tw:border-t tw:border-grey-600 tw:my-1"></div>
      <.logout_form csrf_token={@csrf_token} logout_path={@logout_path} />
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true

  defp user_menu_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="tw:block tw:px-4 tw:py-2 tw:text-sm tw:text-grey-200 tw:hover:bg-grey-600 tw:transition-colors"
    >
      {@label}
    </a>
    """
  end

  attr :csrf_token, :string, required: true
  attr :logout_path, :string, required: true

  defp logout_form(assigns) do
    ~H"""
    <form action={@logout_path} method="post">
      <input type="hidden" name="_csrf_token" value={@csrf_token} />
      <button
        type="submit"
        class="tw:w-full tw:text-left tw:px-4 tw:py-2 tw:text-sm tw:text-grey-200 tw:hover:bg-grey-600 tw:transition-colors tw:cursor-pointer"
      >
        Log out
      </button>
    </form>
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
