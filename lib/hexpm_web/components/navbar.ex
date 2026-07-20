defmodule HexpmWeb.Components.Navbar do
  @moduledoc """
  Navbar component with mobile menu toggle using Phoenix JS commands.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.ViewHelpers, only: [gravatar_url: 2]
  import HexpmWeb.ViewIcons, only: [icon: 3]

  alias Hexpm.Accounts.User
  alias Phoenix.LiveView.JS

  @doc """
  Renders the main header/navbar.
  """
  attr :conn, :map, default: nil
  attr :current_user, :any, default: nil
  attr :search, :string, default: nil
  attr :show_search, :boolean, default: true
  attr :autofocus_search, :boolean, default: false
  attr :live_search, :boolean, default: false
  attr :live_suggestions, :boolean, default: true

  def header(assigns) do
    ~H"""
    <nav id="main-navbar" class="bg-grey-800 w-full font-sans">
      <div class="max-w-7xl mx-auto px-4">
        <div class="flex items-center justify-between h-[72px] gap-8 lg:gap-20">
          <.logo />
          <.desktop_nav
            conn={@conn}
            current_user={@current_user}
            search={@search}
            show_search={@show_search}
            autofocus_search={@autofocus_search}
            live_search={@live_search}
            live_suggestions={@live_suggestions}
          />
          <.mobile_nav_controls current_user={@current_user} show_search={@show_search} />
        </div>

        <.mobile_search_bar :if={@show_search} search={@search} live_search={@live_search} />
        <.mobile_menu
          current_user={@current_user}
          show_search={@show_search}
          search={@search}
          live_search={@live_search}
        />
      </div>
    </nav>
    """
  end

  defp logo(assigns) do
    ~H"""
    <a href="/" class="shrink-0 flex items-center gap-3">
      <img src={~p"/images/hex-full.svg"} alt="hex logo" class="h-8 w-auto" />
      <span class="text-white text-2xl font-bold tracking-tight">
        Hex
      </span>
    </a>
    """
  end

  attr :conn, :map, default: nil
  attr :current_user, :any, required: true
  attr :search, :string, required: true
  attr :show_search, :boolean, required: true
  attr :autofocus_search, :boolean, required: true
  attr :live_search, :boolean, required: true
  attr :live_suggestions, :boolean, required: true

  defp desktop_nav(assigns) do
    ~H"""
    <div class="hidden lg:flex items-center flex-1 justify-end gap-10">
      <.search_form
        :if={@show_search}
        conn={@conn}
        search={@search}
        autofocus={@autofocus_search}
        live_suggestions={@live_suggestions}
      />
      <.nav_links />
      <.theme_toggle />
      <.auth_section current_user={@current_user} />
    </div>
    """
  end

  defp nav_links(assigns) do
    ~H"""
    <a
      href={~p"/packages"}
      class="text-grey-200 text-md hover:text-white transition-colors"
    >
      Packages
    </a>
    <a
      href={~p"/pricing"}
      class="text-grey-200 text-md hover:text-white transition-colors"
    >
      Pricing
    </a>
    <a href={~p"/docs"} class="text-grey-200 text-md hover:text-white transition-colors">
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
      class="inline-flex items-center justify-center whitespace-nowrap bg-grey-400 px-6 py-1 rounded-lg text-white text-md hover:bg-grey-500 hover:scale-105 transition-all duration-200"
    >
      Log In
    </a>
    """
  end

  attr :current_user, :any, required: true
  attr :show_search, :boolean, required: true

  defp mobile_nav_controls(assigns) do
    ~H"""
    <div class="flex lg:hidden items-center gap-6">
      <img
        :if={@current_user}
        src={gravatar_url(User.email(@current_user, :gravatar), :small)}
        class="w-5 h-5 rounded-full"
        alt={@current_user.username}
      />
      <.theme_toggle compact />
      <.mobile_search_toggle :if={@show_search} />
      <.mobile_menu_toggle />
    </div>
    """
  end

  attr :class, :string, default: ""
  attr :compact, :boolean, default: false

  defp theme_toggle(assigns) do
    ~H"""
    <div class={["relative flex items-center", @class]}>
      <button
        type="button"
        data-theme-toggle
        class={[
          "inline-flex items-center justify-center text-grey-200 transition-colors hover:text-white cursor-pointer",
          @compact && "h-10 w-10",
          !@compact && "h-5 w-5"
        ]}
        aria-label="Change theme"
        aria-haspopup="true"
      >
        <span class="sr-only">Change color theme</span>
        <span data-theme-icon="light">
          {icon(:heroicon, "sun", width: 18, height: 18)}
        </span>
        <span data-theme-icon="dark">
          {icon(:heroicon, "moon", width: 18, height: 18)}
        </span>
        <span data-theme-icon="system">
          {icon(:heroicon, "computer-desktop", width: 18, height: 18)}
        </span>
      </button>

      <div
        data-theme-menu
        class="hidden absolute right-0 top-full mt-2 w-36 bg-grey-700 border border-grey-600 rounded-lg shadow-lg py-1 z-50"
      >
        <button
          type="button"
          data-theme-choice="light"
          class="w-full flex items-center gap-2 px-4 py-2 text-sm text-grey-200 hover:bg-grey-600 transition-colors cursor-pointer"
        >
          {icon(:heroicon, "sun", width: 16, height: 16)} Light
        </button>
        <button
          type="button"
          data-theme-choice="dark"
          class="w-full flex items-center gap-2 px-4 py-2 text-sm text-grey-200 hover:bg-grey-600 transition-colors cursor-pointer"
        >
          {icon(:heroicon, "moon", width: 16, height: 16)} Dark
        </button>
        <button
          type="button"
          data-theme-choice="system"
          class="w-full flex items-center gap-2 px-4 py-2 text-sm text-grey-200 hover:bg-grey-600 transition-colors cursor-pointer"
        >
          {icon(:heroicon, "computer-desktop", width: 16, height: 16)} System
        </button>
      </div>
    </div>
    """
  end

  attr :search, :string, required: true
  attr :live_search, :boolean, required: true

  defp mobile_search_bar(assigns) do
    ~H"""
    <div id="mobile-search-bar" class="hidden lg:hidden! bg-grey-800 pb-4">
      <div class="flex items-center gap-2">
        <form
          id="mobile-search-bar-form"
          role="search"
          action={~p"/packages"}
          class="flex-1"
          phx-change={if @live_search, do: "search_change"}
          phx-submit={@live_search && "search_submit"}
          phx-hook={@live_search && "FormSync"}
          data-sync-to={@live_search && "mobile-menu-search-form"}
        >
          <div class="relative">
            <div class="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none">
              {icon(:heroicon, "magnifying-glass", width: 18, height: 18, class: "text-grey-300")}
            </div>
            <input
              id="mobile-search-input"
              name="search"
              type="text"
              value={@search}
              phx-debounce={if @live_search, do: "300"}
              placeholder="Find packages..."
              class="w-full bg-grey-800 border border-grey-600 rounded-lg px-3 pl-10 py-[11px] text-white text-base font-medium leading-4 placeholder:text-grey-300 focus:outline-none focus:border-grey-500 focus:shadow-[inset_0px_0px_6px_0px_rgba(255,255,255,0.3)]"
            />
            <input :if={!@live_search} type="hidden" name="sort" value="recent_downloads" />
          </div>
        </form>
        <button
          type="button"
          phx-click={show_modal("search-cheatsheet")}
          aria-label="Search filter cheatsheet"
          class="flex items-center justify-center w-[43px] self-stretch shrink-0 text-grey-200 hover:text-white border border-grey-600 rounded-lg text-sm font-medium cursor-pointer"
        >
          ?
        </button>
      </div>
    </div>
    """
  end

  attr :current_user, :any, required: true
  attr :show_search, :boolean, required: true
  attr :search, :string, required: true
  attr :live_search, :boolean, required: true

  defp mobile_menu(assigns) do
    ~H"""
    <div id="navbar-mobile" class="hidden lg:hidden! bg-grey-800 pb-6">
      <div class="flex flex-col">
        <div :if={@show_search} class="flex items-center gap-2 pb-4">
          <form
            id="mobile-menu-search-form"
            role="search"
            action={~p"/packages"}
            class="flex-1"
            phx-change={if @live_search, do: "search_change"}
            phx-submit={@live_search && "search_submit"}
            phx-hook={@live_search && "FormSync"}
            data-sync-to={@live_search && "mobile-search-bar-form"}
            phx-auto-recover={if @live_search, do: "ignore"}
          >
            <div class="relative">
              <div class="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none">
                {icon(:heroicon, "magnifying-glass", width: 18, height: 18, class: "text-grey-300")}
              </div>
              <input
                name="search"
                type="text"
                value={@search}
                phx-debounce={if @live_search, do: "300"}
                placeholder="Find packages..."
                class="w-full bg-grey-800 border border-grey-600 rounded-lg px-3 pl-10 py-[11px] text-white text-base font-medium leading-4 placeholder:text-grey-300 focus:outline-none focus:border-grey-500 focus:shadow-[inset_0px_0px_6px_0px_rgba(255,255,255,0.3)]"
              />
              <input :if={!@live_search} type="hidden" name="sort" value="recent_downloads" />
            </div>
          </form>
          <button
            type="button"
            phx-click={show_modal("search-cheatsheet")}
            aria-label="Search filter cheatsheet"
            class="flex items-center justify-center w-[43px] self-stretch shrink-0 text-grey-200 hover:text-white border border-grey-600 rounded-lg text-sm font-medium cursor-pointer"
          >
            ?
          </button>
        </div>
        <.mobile_nav_links />
        <.mobile_auth_section current_user={@current_user} />
      </div>
    </div>
    """
  end

  defp mobile_nav_links(assigns) do
    ~H"""
    <a href={~p"/packages"} class="text-grey-200 text-md py-2 hover:text-white">
      Packages
    </a>
    <a href={~p"/pricing"} class="text-grey-200 text-md py-2 hover:text-white">
      Pricing
    </a>
    <a href={~p"/docs"} class="text-grey-200 text-md py-2 hover:text-white">
      Docs
    </a>
    """
  end

  attr :current_user, :any, required: true

  defp mobile_auth_section(assigns) do
    ~H"""
    <div :if={@current_user} class="border-t border-grey-700 pt-2 mt-2">
      <.mobile_user_menu_link href={~p"/users/#{@current_user}"} label="Profile" />
      <.mobile_user_menu_link href={~p"/dashboard/profile"} label="Dashboard" />
      <.mobile_logout_form />
    </div>
    <a
      :if={!@current_user}
      href={~p"/login"}
      class="bg-grey-600 px-6 py-[11px] rounded-lg text-white text-md text-center hover:bg-grey-500 mt-2"
    >
      Log In
    </a>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true

  defp mobile_user_menu_link(assigns) do
    ~H"""
    <a href={@href} class="block text-grey-200 text-md py-2 hover:text-white">
      {@label}
    </a>
    """
  end

  defp mobile_logout_form(assigns) do
    ~H"""
    <form action={~p"/logout"} method="post">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <button
        type="submit"
        class="w-full text-left text-grey-200 text-md py-2 hover:text-white cursor-pointer"
      >
        Log out
      </button>
    </form>
    """
  end

  attr :conn, :map, default: nil
  attr :search, :string, default: nil
  attr :autofocus, :boolean, default: false
  attr :live_suggestions, :boolean, default: true

  defp search_form(%{live_suggestions: true} = assigns) do
    ~H"""
    <div class="min-w-0 flex-1 mr-auto">
      <div class="max-w-[420px] w-full">
        {Phoenix.Component.live_render(@conn, HexpmWeb.SearchSuggestionsLive,
          id: "nav-search",
          session: %{
            "variant" => "nav",
            "limit" => 8,
            "autofocus" => @autofocus,
            "search" => @search
          }
        )}
      </div>
    </div>
    """
  end

  defp search_form(assigns) do
    ~H"""
    <div class="min-w-0 flex-1 mr-auto">
      <div class="max-w-[420px] w-full">
        <form method="get" action={~p"/packages"} role="search" autocomplete="off">
          <div class="relative flex items-center">
            <div class="absolute left-3 pointer-events-none">
              {icon(:heroicon, "magnifying-glass", width: 18, height: 18, class: "text-grey-300")}
            </div>
            <input
              type="search"
              placeholder="Find packages..."
              name="search"
              id="nav-search-input"
              value={@search}
              autocomplete="off"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              autofocus={@autofocus}
              class="w-full h-[40px] bg-grey-800 border border-grey-600 rounded-lg px-3 pl-10 py-[11px] text-white leading-4 placeholder:text-grey-300 focus:outline-none focus:border-grey-500 focus:shadow-[inset_0px_0px_6px_0px_rgba(255,255,255,0.3)]"
            />
            <input type="hidden" name="sort" value="recent_downloads" />
            <label class="sr-only" for="nav-search-input">Find packages</label>
          </div>
        </form>
      </div>
    </div>
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
      class={"text-grey-200 p-0 cursor-pointer " <> @class}
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
        {"transition-all ease-out duration-200 transform", "opacity-0 -translate-y-2",
         "opacity-100 translate-y-0"},
      out:
        {"transition-all ease-in duration-150 transform", "opacity-100 translate-y-0",
         "opacity-0 -translate-y-2"}
    )
    |> JS.hide(to: "#navbar-mobile")
    |> JS.show(to: "#menu-open-icon")
    |> JS.hide(to: "#menu-close-icon")
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
      class={"bg-grey-700 rounded-lg p-[10px] w-10 h-10 flex items-center justify-center cursor-pointer " <> @class}
      phx-click={toggle_mobile_menu()}
      aria-expanded="false"
      aria-controls="navbar-mobile"
    >
      <span class="sr-only">Toggle navigation</span>
      <%!-- Hamburger icon (shown when closed) --%>
      <span id="menu-open-icon" class="block">
        {icon(:heroicon, "bars-3", width: 20, height: 20, class: "text-grey-200")}
      </span>
      <%!-- X icon (shown when open) --%>
      <span id="menu-close-icon" class="hidden">
        {icon(:heroicon, "x-mark", width: 20, height: 20, class: "text-grey-200")}
      </span>
    </button>
    """
  end

  defp toggle_mobile_menu do
    JS.toggle(
      to: "#navbar-mobile",
      in:
        {"transition-all ease-out duration-300 transform", "opacity-0 -translate-y-2",
         "opacity-100 translate-y-0"},
      out:
        {"transition-all ease-in duration-200 transform", "opacity-100 translate-y-0",
         "opacity-0 -translate-y-2"}
    )
    |> JS.toggle(to: "#menu-open-icon")
    |> JS.toggle(to: "#menu-close-icon")
    |> JS.hide(to: "#mobile-search-bar")
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
    <div class="relative">
      <.user_dropdown_button avatar_url={@avatar_url} class={@class} username={@username} />

      <%!-- Backdrop for click-away --%>
      <div
        id="user-dropdown-backdrop"
        class="hidden fixed inset-0 z-40"
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
      class={"flex items-center gap-[10px] bg-grey-600 px-6 py-[11px] rounded-lg text-white text-md leading-[18px] cursor-pointer " <> @class}
      phx-click={toggle_user_dropdown()}
      aria-expanded="false"
      aria-haspopup="true"
      aria-controls="user-dropdown-menu"
    >
      <img src={@avatar_url} class="w-5 h-5 rounded-full" alt={@username} />
      <span>{@username}</span>
      {icon(:heroicon, "chevron-down", width: 16, height: 16, class: "text-grey-200")}
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
      class="hidden absolute right-0 mt-2 w-48 bg-grey-700 border border-grey-600 rounded-lg shadow-lg py-1 z-50"
    >
      <.user_menu_link href={@user_path} label="Profile" />
      <.user_menu_link href={@dashboard_path} label="Dashboard" />
      <div class="border-t border-grey-600 my-1"></div>
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
      class="block px-4 py-2 text-sm text-grey-200 hover:bg-grey-600 transition-colors"
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
        class="w-full text-left px-4 py-2 text-sm text-grey-200 hover:bg-grey-600 transition-colors cursor-pointer"
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
        {"transition-all ease-out duration-200 transform", "opacity-0 -translate-y-2",
         "opacity-100 translate-y-0"},
      out:
        {"transition-all ease-in duration-150 transform", "opacity-100 translate-y-0",
         "opacity-0 -translate-y-2"}
    )
    |> JS.toggle(to: "#user-dropdown-backdrop")
  end

  defp hide_user_dropdown do
    JS.hide(
      to: "#user-dropdown-menu",
      transition:
        {"transition-all ease-in duration-150 transform", "opacity-100 translate-y-0",
         "opacity-0 -translate-y-2"}
    )
    |> JS.hide(to: "#user-dropdown-backdrop")
  end
end
