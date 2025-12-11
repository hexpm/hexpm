defmodule HexpmWeb.Components.AuthLayout do
  @moduledoc """
  Reusable layout component for authentication pages.
  Provides consistent card wrapper, header, OAuth buttons, divider, and footer links.
  """
  use Phoenix.Component

  import HexpmWeb.Components.Icons

  @doc """
  Renders an authentication page layout with a centered card.

  ## Examples

      <.auth_layout
        title="Log In"
        subtitle="Use your credentials to log in to your account"
        show_oauth={true}
        oauth_provider="GitHub"
        oauth_href={~p"/auth/github"}
      >
        <.text_input id="email" name="email" label="Email" />
        <.button type="submit" full_width>Log In</.button>

        <:footer_links>
          <p class="tw:text-small tw:text-center tw:mt-8">
            <span class="tw:text-grey-800">Don't have an account?</span>
            <a href={~p"/signup"} class="tw:font-semibold tw:text-blue-600">Register Now</a>
          </p>
        </:footer_links>
      </.auth_layout>
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :show_oauth, :boolean, default: false
  attr :oauth_provider, :string, default: "GitHub"

  attr :oauth_href, :string,
    default: nil,
    doc: "Required when show_oauth is true and no custom oauth_button slot is provided"

  attr :divider_text, :string, default: "or"
  attr :class, :string, default: ""

  slot :inner_block, required: true
  slot :oauth_button
  slot :footer_links

  def auth_layout(assigns) do
    # Validate OAuth configuration in development
    if assigns.show_oauth && assigns.oauth_button == [] && !assigns.oauth_href do
      require Logger

      Logger.warning("""
      AuthLayout: show_oauth is true but neither oauth_button slot nor oauth_href was provided.
      Either provide an oauth_href or use the oauth_button slot.
      """)
    end

    ~H"""
    <div class={[
      "tw:flex tw:items-center tw:justify-center tw:my-auto tw:py-16",
      @class
    ]}>
      <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:w-full tw:max-w-lg tw:px-10 tw:py-10">
        <%!-- Header --%>
        <h1 class="tw:font-bold tw:text-[40px] tw:leading-[40px] tw:text-grey-900 tw:text-center tw:mb-3">
          {@title}
        </h1>

        <p :if={@subtitle} class="tw:text-grey-600 tw:text-center tw:mb-8 tw:leading-6">
          {@subtitle}
        </p>

        <%!-- OAuth Button --%>
        <div :if={@show_oauth && @oauth_button != []}>
          {render_slot(@oauth_button)}
        </div>

        <a
          :if={@show_oauth && @oauth_button == [] && @oauth_href}
          href={@oauth_href}
          class="tw:flex tw:items-center tw:justify-center tw:gap-3 tw:w-full tw:h-12 tw:bg-grey-900 tw:rounded tw:text-white tw:text-md tw:font-semibold tw:hover:bg-grey-800 tw:transition-colors tw:mb-6"
        >
          <.github_icon class="tw:w-5 tw:h-5" /> Login with {@oauth_provider}
        </a>

        <%!-- Divider --%>
        <div
          :if={@show_oauth && (@oauth_button != [] || @oauth_href)}
          class="tw:flex tw:items-center tw:gap-4 tw:mb-8"
        >
          <div class="tw:flex-1 tw:h-px tw:bg-grey-200"></div>
          <span class="tw:text-small tw:text-grey-400">{@divider_text}</span>
          <div class="tw:flex-1 tw:h-px tw:bg-grey-200"></div>
        </div>

        <%!-- Form Content --%>
        {render_slot(@inner_block)}

        <%!-- Footer Links --%>
        <div :if={@footer_links != []}>
          {render_slot(@footer_links)}
        </div>
      </div>
    </div>
    """
  end
end
