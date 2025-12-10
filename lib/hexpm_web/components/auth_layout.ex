defmodule HexpmWeb.Components.AuthLayout do
  @moduledoc """
  Reusable layout component for authentication pages.
  Provides consistent card wrapper, header, OAuth buttons, divider, and footer links.
  """
  use Phoenix.Component

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
    ~H"""
    <div class={["tw:flex tw:items-center tw:justify-center tw:my-auto tw:py-16", @class]}>
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
          <svg
            width="20"
            height="20"
            viewBox="0 0 20 20"
            fill="currentColor"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              fill-rule="evenodd"
              clip-rule="evenodd"
              d="M10 0C4.477 0 0 4.477 0 10c0 4.42 2.865 8.166 6.839 9.489.5.092.682-.217.682-.482 0-.237-.008-.866-.013-1.7-2.782.603-3.369-1.34-3.369-1.34-.454-1.156-1.11-1.463-1.11-1.463-.908-.62.069-.608.069-.608 1.003.07 1.531 1.03 1.531 1.03.892 1.529 2.341 1.087 2.91.831.092-.646.35-1.086.636-1.336-2.22-.253-4.555-1.11-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0110 4.836c.85.004 1.705.114 2.504.336 1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.743 0 .267.18.578.688.48C17.137 18.163 20 14.418 20 10c0-5.523-4.477-10-10-10z"
            />
          </svg>
          Login with {@oauth_provider}
        </a>

        <%!-- Divider --%>
        <div :if={@show_oauth} class="tw:flex tw:items-center tw:gap-4 tw:mb-8">
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
