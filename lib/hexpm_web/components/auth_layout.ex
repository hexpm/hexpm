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
          <p class="text-small text-center mt-8">
            <span class="text-grey-800">Don't have an account?</span>
            <a href={~p"/signup"} class="font-semibold text-blue-600">Register Now</a>
          </p>
        </:footer_links>
      </.auth_layout>
  """
  attr :class, :string, default: ""
  attr :divider_text, :string, default: "or"

  attr :oauth_href, :string,
    default: nil,
    doc: "Required when show_oauth is true and no custom oauth_button slot is provided"

  attr :oauth_provider, :string, default: "GitHub"
  attr :show_oauth, :boolean, default: false
  attr :subtitle, :string, default: nil
  attr :title, :string, required: true

  slot :footer_links
  slot :inner_block, required: true
  slot :oauth_button

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
      "flex items-center justify-center my-auto py-16",
      @class
    ]}>
      <div class="bg-white border border-grey-200 rounded-lg w-full max-w-lg px-10 py-10">
        <%!-- Header --%>
        <h1 class="font-bold text-[40px] leading-[40px] text-grey-900 text-center mb-3">
          {@title}
        </h1>

        <p :if={@subtitle} class="text-grey-600 text-center mb-8 leading-6">
          {@subtitle}
        </p>

        <%!-- OAuth Button --%>
        <div :if={@show_oauth && @oauth_button != []}>
          {render_slot(@oauth_button)}
        </div>

        <a
          :if={@show_oauth && @oauth_button == [] && @oauth_href}
          href={@oauth_href}
          class="flex items-center justify-center gap-3 w-full h-12 bg-grey-900 rounded text-white text-md font-semibold hover:bg-grey-800 transition-colors mb-6"
        >
          <.github_icon class="w-5 h-5" /> Login with {@oauth_provider}
        </a>

        <%!-- Divider --%>
        <div
          :if={@show_oauth && (@oauth_button != [] || @oauth_href)}
          class="flex items-center gap-4 mb-8"
        >
          <div class="flex-1 h-px bg-grey-200"></div>
          <span class="text-small text-grey-400">{@divider_text}</span>
          <div class="flex-1 h-px bg-grey-200"></div>
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
