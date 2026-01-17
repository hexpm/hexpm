defmodule HexpmWeb.Components.Icons do
  @moduledoc """
  Custom SVG icon components for social media and branding.

  This module provides reusable icon components for icons that aren't available
  in Heroicons. For standard icons, prefer using HexpmWeb.ViewIcons with heroicons.
  """
  use Phoenix.Component

  @doc """
  Renders a GitHub icon.
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"

  def github_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      class={@class}
      aria-hidden="true"
    >
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M12 2C6.477 2 2 6.528 2 12.07c0 4.449 2.865 8.222 6.839 9.558.5.095.683-.219.683-.487 0-.24-.01-1.034-.014-1.876-2.782.609-3.369-1.193-3.369-1.193-.454-1.166-1.11-1.477-1.11-1.477-.908-.625.07-.612.07-.612 1.004.071 1.532 1.045 1.532 1.045.893 1.55 2.341 1.103 2.91.844.091-.656.35-1.103.636-1.357-2.22-.257-4.555-1.117-4.555-4.969 0-1.098.388-1.995 1.025-2.698-.103-.259-.445-1.296.098-2.704 0 0 .84-.27 2.75 1.03A9.517 9.517 0 0 1 12 6.844a9.5 9.5 0 0 1 2.5.341c1.91-1.3 2.749-1.03 2.749-1.03.544 1.408.202 2.445.1 2.704.64.703 1.024 1.6 1.024 2.698 0 3.861-2.339 4.708-4.566 4.961.359.313.678.928.678 1.872 0 1.352-.013 2.442-.013 2.775 0 .27.18.586.688.486C19.138 20.287 22 16.517 22 12.07 22 6.528 17.523 2 12 2Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders a Twitter/X icon.
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"

  def twitter_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      class={@class}
      aria-hidden="true"
    >
      <path
        d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders a Bluesky icon.
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"

  def bluesky_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      class={@class}
      aria-hidden="true"
    >
      <path
        d="M12 10.8c-1.087-2.114-4.046-6.053-6.798-7.995C2.566.944 1.561 1.266.902 1.565.139 1.908 0 3.08 0 3.768c0 .69.378 5.65.624 6.479.815 2.736 3.713 3.66 6.383 3.364.136-.02.275-.038.415-.054-.265.02-.532.034-.807.034C4.15 13.59 2 14.845 2 16.58c0 1.039.625 1.563 1.442 1.842 1.518.52 3.478.96 5.558 1.325 3.265.57 6.405-.02 7.774-3.36 1.369 3.34 4.509 3.93 7.774 3.36 2.08-.365 4.04-.805 5.558-1.325.817-.279 1.442-.803 1.442-1.842 0-1.735-2.15-2.99-4.615-2.99-.275 0-.542-.013-.807-.034.14.016.279.034.415.054 2.67.297 5.568-.628 6.383-3.364.246-.828.624-5.79.624-6.478 0-.69-.139-1.861-.902-2.206-.659-.298-1.664-.62-4.3 1.24C16.046 4.748 13.087 8.687 12 10.8Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders an Elixir Forum icon (using Elixir logo).
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"

  def elixirforum_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
      aria-hidden="true"
    >
      <g clip-path="url(#clip0_280_334)">
        <path
          d="M13.1954 11.0494C13.1954 13.5507 11.244 16.0001 8.03335 16.0001C4.53402 16.0001 2.80469 13.5267 2.80469 10.4734C2.80469 7.00006 5.39935 1.83873 8.13802 0.0420585C8.17977 0.0152102 8.22823 0.000643208 8.27786 2.0814e-05C8.32749 -0.000601579 8.3763 0.0127458 8.41871 0.0385387C8.46112 0.0643316 8.49542 0.101531 8.51769 0.145888C8.53997 0.190245 8.54932 0.239972 8.54469 0.289392C8.39105 1.82615 8.79157 3.36724 9.67402 4.63473C10.022 5.16473 10.402 5.62006 10.8494 6.20273C11.476 7.02073 11.9407 7.47339 12.612 8.76406L12.622 8.78273C12.9995 9.47852 13.1966 10.2578 13.1954 11.0494Z"
          fill="currentColor"
        />
      </g>
      <defs>
        <clipPath id="clip0_280_334">
          <rect width="16" height="16" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end

  @doc """
  Renders a Slack icon.
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"

  def slack_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      class={@class}
      aria-hidden="true"
    >
      <path
        d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zm1.271 0a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zm0 1.271a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zm10.122 2.521a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zm-1.268 0a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312zm-2.523 10.122a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zm0-1.268a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders a Libera (IRC) icon.
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"

  def libera_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      class={@class}
      aria-hidden="true"
    >
      <path
        d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.894 15.367c-.289.36-.737.596-1.235.596H7.341c-.498 0-.946-.236-1.235-.596a1.79 1.79 0 01-.367-1.09V9.723c0-.387.131-.764.367-1.09.289-.36.737-.596 1.235-.596h9.318c.498 0 .946.236 1.235.596.236.326.367.703.367 1.09v4.554c0 .387-.131.764-.367 1.09z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders a social icon based on the icon name.

  Supports: :github, :twitter, :bluesky, :elixirforum, :slack, :freenode (libera)

  ## Examples

      <.social_icon icon={:github} />
      <.social_icon icon={:twitter} class="tw:h-6 tw:w-6" />
  """
  attr :class, :string, default: "tw:h-4 tw:w-4"
  attr :icon, :atom, required: true

  def social_icon(%{icon: :github} = assigns) do
    ~H"""
    <.github_icon class={@class} />
    """
  end

  def social_icon(%{icon: :twitter} = assigns) do
    ~H"""
    <.twitter_icon class={@class} />
    """
  end

  def social_icon(%{icon: :bluesky} = assigns) do
    ~H"""
    <.bluesky_icon class={@class} />
    """
  end

  def social_icon(%{icon: :elixirforum} = assigns) do
    ~H"""
    <.elixirforum_icon class={@class} />
    """
  end

  def social_icon(%{icon: :slack} = assigns) do
    ~H"""
    <.slack_icon class={@class} />
    """
  end

  def social_icon(%{icon: :freenode} = assigns) do
    ~H"""
    <.libera_icon class={@class} />
    """
  end
end
