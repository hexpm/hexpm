defmodule HexpmWeb.Components.Home do
  @moduledoc """
  Components for the homepage.
  """
  use Phoenix.Component
  import HexpmWeb.ViewIcons, only: [icon: 3]

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  @doc """
  Renders a language card for the "Using with..." section.

  ## Examples

      <.language_card
        language="Elixir"
        image_src={~p"/images/elixir.svg"}
        href={~p"/docs/usage"}
      >
        Specify your Mix dependencies as two-item tuples like
        <code class="font-mono text-grey-400">{"{:plug, \"~> 1.1.0\"}"}</code>
        in your dependency list, Elixir will ask if you want to install Hex if you haven't already.
      </.language_card>
  """
  attr :href, :string, required: true
  attr :image_src, :string, required: true
  attr :language, :string, required: true
  slot :inner_block, required: true

  def language_card(assigns) do
    ~H"""
    <div class="bg-grey-900 rounded-xl p-4">
      <div class="flex gap-1.5 mb-3">
        <div class="w-2 h-2 rounded-full bg-green-500"></div>
        <div class="w-2 h-2 rounded-full bg-yellow-500"></div>
        <div class="w-2 h-2 rounded-full bg-red-500"></div>
      </div>
      <div class="flex gap-4">
        <div class="flex items-center shrink-0">
          <img src={@image_src} alt={@language} class="w-10 h-12 object-contain" />
        </div>
        <div class="flex flex-col gap-1">
          <a href={@href} class="text-grey-100 font-semibold text-base hover:text-white">
            Using with {@language}
          </a>
          <p class="text-grey-200 text-sm leading-5">
            {render_slot(@inner_block)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders inline code snippets with dark theme styling.

  ## Examples

      <.code_inline>{"{:plug, \"~> 1.1.0\"}"}</.code_inline>
  """
  slot :inner_block, required: true

  def code_inline(assigns) do
    ~H"""
    <span class="bg-grey-700 text-grey-200 mx-1 px-0.5 py-0.5 rounded border border-grey-600 font-mono text-sm">
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a company logo with hover effects.

  ## Examples

      <.company_logo src="discord.svg" alt="Discord" />
  """
  attr :src, :string, required: true
  attr :alt, :string, required: true

  def company_logo(assigns) do
    ~H"""
    <div class="flex items-center justify-center grayscale hover:grayscale-0 transition-all duration-300">
      <img
        src={~p"/images/clients/#{@src}"}
        alt={@alt}
        class="h-8 w-auto opacity-70 hover:opacity-100 transition-opacity duration-300"
      />
    </div>
    """
  end

  @doc """
  Renders the companies section with client logos.

  ## Examples

      <.companies_section />
  """
  def companies_section(assigns) do
    ~H"""
    <div class="bg-white pt-4 pb-8 lg:pb-16">
      <div class="max-w-7xl mx-auto px-4">
        <%!-- Mobile: 3x3 grid with alternating pattern --%>
        <div class="grid grid-cols-3 gap-6 md:hidden">
          <%!-- Row 1: x x x --%>
          <.company_logo src="sketch.svg" alt="Sketch" />
          <.company_logo src="discord.svg" alt="Discord" />
          <.company_logo src="square_enix.svg" alt="Square Enix" />
          <%!-- Row 2: offset x x x --%>
          <.company_logo src="riot_games.svg" alt="Riot Games" />
          <.company_logo src="we_chat.svg" alt="WeChat" />
          <.company_logo src="lonely_planet.svg" alt="Lonely Planet" />
          <%!-- Row 3: x x x --%>
          <.company_logo src="whatsapp.svg" alt="WhatsApp" />
          <.company_logo src="pepsico.svg" alt="PepsiCo" />
          <.company_logo src="bet365.svg" alt="Bet365" />
        </div>
        <%!-- Desktop: 2 rows (5 + 4) --%>
        <div class="hidden md:block space-y-12">
          <%!-- First row: 5 logos --%>
          <div class="flex items-center justify-center gap-8 md:gap-12 flex-wrap">
            <.company_logo src="sketch.svg" alt="Sketch" />
            <.company_logo src="discord.svg" alt="Discord" />
            <.company_logo src="square_enix.svg" alt="Square Enix" />
            <.company_logo src="riot_games.svg" alt="Riot Games" />
            <.company_logo src="we_chat.svg" alt="WeChat" />
          </div>
          <%!-- Second row: 4 logos --%>
          <div class="flex items-center justify-center gap-8 md:gap-24 flex-wrap">
            <.company_logo src="lonely_planet.svg" alt="Lonely Planet" />
            <.company_logo src="whatsapp.svg" alt="WhatsApp" />
            <.company_logo src="pepsico.svg" alt="PepsiCo" />
            <.company_logo src="bet365.svg" alt="Bet365" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a package column header with an icon.

  ## Examples

      <.package_column_header
        color="primary"
        icon="arrow-trending-up"
        title="Most Downloaded"
      />
  """
  attr :color, :string,
    required: true,
    values: ["primary", "green", "blue"],
    doc: "Color scheme for the header"

  attr :icon, :string, required: true
  attr :title, :string, required: true

  def package_column_header(assigns) do
    assigns = Map.put(assigns, :bg_color, get_color_class(assigns.color, :bg))
    assigns = Map.put(assigns, :polygon_color, get_color_class(assigns.color, :polygon))

    ~H"""
    <div class={["rounded-xl p-4 flex items-center gap-3 mb-6", @bg_color]}>
      <div class="size-[60px] flex items-center justify-center relative">
        <svg class={["size-full", @polygon_color]} viewBox="0 0 60 60" fill="none">
          <polygon points="30,5 52,15 52,45 30,55 8,45 8,15" fill="currentColor" />
        </svg>
        <span class="absolute text-white">
          {HexpmWeb.ViewIcons.icon(:heroicon, @icon, class: "size-6")}
        </span>
      </div>
      <h2 class="text-grey-100 font-semibold text-xl">{@title}</h2>
    </div>
    """
  end

  defp get_color_class("primary", :bg), do: "bg-primary-600"
  defp get_color_class("primary", :polygon), do: "text-primary-700"
  defp get_color_class("green", :bg), do: "bg-green-600"
  defp get_color_class("green", :polygon), do: "text-green-700"
  defp get_color_class("blue", :bg), do: "bg-blue-600"
  defp get_color_class("blue", :polygon), do: "text-blue-700"

  @doc """
  Renders a package item in the package lists (Most Downloaded, New Packages, Recently Updated).

  ## Examples

      <.package_item
        package="phoenix"
        version="1.7.0"
        description="A productive web framework"
        downloads={1_500_000}
      />
  """
  attr :description, :string, default: nil
  attr :downloads, :integer, default: nil
  attr :package, :string, required: true
  attr :version, :string, default: nil

  def package_item(assigns) do
    ~H"""
    <li class="py-4 border-b border-grey-100 last:border-b-0">
      <div class="flex items-center justify-between gap-4">
        <div class="flex flex-col gap-1 min-w-0">
          <div class="flex items-end gap-2">
            <a
              href={~p"/packages/#{@package}"}
              class="text-grey-900 font-medium text-lg hover:text-primary-600 transition-colors"
            >
              {@package}
            </a>
            <span :if={@version} class="text-grey-500 text-xs bg-grey-50 p-1 rounded-md">
              {@version}
            </span>
          </div>
          <p class="text-grey-500 text-sm leading-5 line-clamp-2 min-h-[2.5rem]">
            {if @description, do: HexpmWeb.ViewHelpers.text_length(@description, 100), else: "\u00A0"}
          </p>
        </div>
        <span
          :if={@downloads && is_integer(@downloads) && @downloads > 0}
          class="text-grey-600 text-lg shrink-0 text-center min-w-[4rem]"
        >
          {HexpmWeb.ViewHelpers.human_number_space(@downloads, 3)}
        </span>
      </div>
    </li>
    """
  end

  @doc """
  Renders a stat item with icon, number, and label.

  ## Examples

      <.stat_item icon="archive-box" number={1234} label="packages available" />
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :number, :any, required: true

  def stat_item(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <div class="size-12 bg-grey-100 rounded-lg flex items-center justify-center">
        {icon(:heroicon, @icon, class: "size-6 text-grey-400")}
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-grey-900 text-2xl font-bold leading-6">
          {HexpmWeb.ViewHelpers.human_number_space(@number)}
        </span>
        <span class="text-grey-600">{@label}</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a feature card for the "Getting Started" section.

  ## Examples

      <.feature_card icon="arrow-right" title="Getting started" href={~p"/docs/usage"}>
        Fetch dependencies from Hex without creating an account.
      </.feature_card>
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def feature_card(assigns) do
    ~H"""
    <div class="bg-grey-50 rounded-xl p-6 hover:bg-grey-100 transition-colors">
      <div class="flex items-center gap-2 mb-3">
        {icon(:heroicon, @icon, class: "size-5 text-primary-600")}
        <h2 class="text-grey-900 text-lg font-semibold">
          {@title}
        </h2>
      </div>
      <p class="text-grey-700 text-sm leading-6">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end
end
