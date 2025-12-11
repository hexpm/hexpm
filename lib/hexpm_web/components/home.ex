defmodule HexpmWeb.Components.Home do
  @moduledoc """
  Components for the homepage.
  """
  use Phoenix.Component

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
        <code class="tw:font-mono tw:text-grey-400">{"{:plug, \"~> 1.1.0\"}"}</code>
        in your dependency list, Elixir will ask if you want to install Hex if you haven't already.
      </.language_card>
  """
  attr :href, :string, required: true
  attr :image_src, :string, required: true
  attr :language, :string, required: true
  slot :inner_block, required: true

  def language_card(assigns) do
    ~H"""
    <div class="tw:bg-grey-900 tw:rounded-xl tw:p-8 tw:flex tw:gap-5">
      <div class="tw:flex tw:flex-col tw:shrink-0">
        <div class="tw:flex tw:gap-2 tw:mb-4">
          <div class="tw:w-3 tw:h-3 tw:rounded-full tw:bg-green-500"></div>
          <div class="tw:w-3 tw:h-3 tw:rounded-full tw:bg-yellow-500"></div>
          <div class="tw:w-3 tw:h-3 tw:rounded-full tw:bg-red-500"></div>
        </div>
        <div class="tw:flex tw:items-center tw:justify-center tw:flex-1">
          <img src={@image_src} alt={@language} class="tw:w-16 tw:h-16 tw:object-contain" />
        </div>
      </div>
      <div class="tw:flex tw:flex-col tw:gap-2">
        <a href={@href} class="tw:text-grey-100 tw:font-semibold tw:text-lg tw:hover:text-white">
          Using with {@language}
        </a>
        <p class="tw:text-grey-200 tw:leading-6">
          {render_slot(@inner_block)}
        </p>
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
    <span class="tw:bg-grey-700 tw:text-grey-200 tw:mx-1 tw:px-0.5 tw:py-0.5 tw:rounded tw:border tw:border-grey-600 tw:font-mono tw:text-sm">
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
    <div class="tw:flex tw:items-center tw:justify-center tw:grayscale tw:hover:grayscale-0 tw:transition-all tw:duration-300">
      <img
        src={~p"/images/clients/#{@src}"}
        alt={@alt}
        class="tw:h-8 tw:w-auto tw:opacity-70 tw:hover:opacity-100 tw:transition-opacity tw:duration-300"
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
    <div class="tw:bg-white tw:pt-4 tw:pb-16">
      <div class="tw:max-w-7xl tw:mx-auto tw:px-4">
        <div class="tw:space-y-12">
          <%!-- First row: 5 logos --%>
          <div class="tw:flex tw:items-center tw:justify-center tw:gap-8 tw:md:gap-12 tw:flex-wrap">
            <.company_logo src="sketch.svg" alt="Sketch" />
            <.company_logo src="discord.svg" alt="Discord" />
            <.company_logo src="square_enix.svg" alt="Square Enix" />
            <.company_logo src="riot_games.svg" alt="Riot Games" />
            <.company_logo src="we_chat.svg" alt="WeChat" />
          </div>
          <%!-- Second row: 4 logos --%>
          <div class="tw:flex tw:items-center tw:justify-center tw:gap-8 tw:md:gap-24 tw:flex-wrap">
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
  Renders a package column header with emoji icon.

  ## Examples

      <.package_column_header
        color="primary"
        emoji="😍"
        title="Most Downloaded"
      />
  """
  attr :color, :string,
    required: true,
    values: ["primary", "green", "blue"],
    doc: "Color scheme for the header"

  attr :emoji, :string, required: true
  attr :title, :string, required: true

  def package_column_header(assigns) do
    assigns = Map.put(assigns, :bg_color, get_color_class(assigns.color, :bg))
    assigns = Map.put(assigns, :polygon_color, get_color_class(assigns.color, :polygon))

    ~H"""
    <div class={["tw:rounded-xl tw:p-4 tw:flex tw:items-center tw:gap-3 tw:mb-6", @bg_color]}>
      <div class="tw:size-[60px] tw:flex tw:items-center tw:justify-center tw:relative">
        <svg class={["tw:size-full", @polygon_color]} viewBox="0 0 60 60" fill="none">
          <polygon points="30,5 52,15 52,45 30,55 8,45 8,15" fill="currentColor" />
        </svg>
        <span class="tw:absolute tw:text-2xl">{@emoji}</span>
      </div>
      <h2 class="tw:text-grey-100 tw:font-semibold tw:text-xl">{@title}</h2>
    </div>
    """
  end

  defp get_color_class("primary", :bg), do: "tw:bg-primary-600"
  defp get_color_class("primary", :polygon), do: "tw:text-primary-700"
  defp get_color_class("green", :bg), do: "tw:bg-green-600"
  defp get_color_class("green", :polygon), do: "tw:text-green-700"
  defp get_color_class("blue", :bg), do: "tw:bg-blue-600"
  defp get_color_class("blue", :polygon), do: "tw:text-blue-700"

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
    <li class="tw:py-4 tw:border-b tw:border-grey-100 tw:last:border-b-0">
      <div class="tw:flex tw:items-center tw:justify-between tw:gap-4">
        <div class="tw:flex tw:flex-col tw:gap-1 tw:min-w-0">
          <div class="tw:flex tw:items-end tw:gap-2">
            <a
              href={~p"/packages/#{@package}"}
              class="tw:text-grey-900 tw:font-medium tw:text-lg tw:hover:text-primary-600 tw:transition-colors"
            >
              {@package}
            </a>
            <span class="tw:text-grey-500 tw:text-xs tw:bg-grey-50 tw:p-1 tw:rounded-md">
              {if @version, do: @version, else: "N/A"}
            </span>
          </div>
          <p class="tw:text-grey-500 tw:text-sm tw:leading-5 tw:line-clamp-2 tw:min-h-[2.5rem]">
            {if @description, do: HexpmWeb.ViewHelpers.text_length(@description, 100), else: "\u00A0"}
          </p>
        </div>
        <span
          :if={@downloads && is_integer(@downloads) && @downloads > 0}
          class="tw:text-grey-600 tw:text-lg tw:shrink-0 tw:text-center tw:min-w-[4rem]"
        >
          {HexpmWeb.ViewHelpers.human_number_space(@downloads, 3)}
        </span>
      </div>
    </li>
    """
  end
end
