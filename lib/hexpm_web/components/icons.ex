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
        d="M21 5.5c-.7.3-1.4.5-2.2.6a3.6 3.6 0 0 0-6.2 3.3A10.1 10.1 0 0 1 4.7 6c-.7 1.2-.4 2.7.7 3.5-.6 0-1-.2-1.4-.4v.1c0 1.7 1.2 3.2 2.9 3.5a3.5 3.5 0 0 1-1.4.1c.4 1.3 1.6 2.2 3 2.2A7.2 7.2 0 0 1 3 17.5 10.2 10.2 0 0 0 8.6 19c6.3 0 9.8-5.3 9.8-9.8v-.4c.7-.5 1.3-1.1 1.8-1.8-.6.3-1.3.5-2 .6.7-.4 1.2-1 1.6-1.7Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders a social icon based on the icon name.

  Supports: :github, :twitter

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
end
