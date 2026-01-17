defmodule HexpmWeb.Components.Buttons do
  @moduledoc """
  Reusable button components with consistent styling and behavior.
  """
  use Phoenix.Component
  import HexpmWeb.ViewIcons, only: [icon: 3]

  @doc """
  Renders a button with various style variants.

  ## Examples

      <.button>Save</.button>
      <.button variant="secondary">Cancel</.button>
      <.button variant="danger" phx-click="delete">Delete</.button>
      <.button variant="outline" class="tw:w-full">Sign Up</.button>

      <.button disabled>Disabled</.button>
      <.button loading>Processing...</.button>
  """
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false
  attr :full_width, :boolean, default: false
  attr :loading, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-target phx-value-id form)
  attr :size, :string, default: "md", values: ["sm", "md", "lg"]
  attr :type, :string, default: "button", values: ["button", "submit", "reset"]

  attr :variant, :string,
    default: "primary",
    values: ["primary", "secondary", "danger", "outline", "ghost", "blue"]

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled || @loading}
      class={
        [
          # Base styles
          "tw:inline-flex tw:items-center tw:justify-center tw:gap-2 tw:font-semibold tw:rounded",
          "tw:transition-colors tw:focus:outline-none tw:focus:ring-2 tw:focus:ring-offset-2",
          # Size variants
          button_size(@size),
          # Color variants
          button_variant(@variant),
          # States
          (@disabled || @loading) && "tw:opacity-50 tw:cursor-not-allowed",
          !(@disabled || @loading) && "tw:cursor-pointer",
          @full_width && "tw:w-full",
          @class
        ]
      }
      {@rest}
    >
      <span :if={@loading} class="tw:animate-spin">
        {icon(:heroicon, "arrow-path", width: 16, height: 16)}
      </span>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a link styled as a button.

  ## Examples

      <.button_link href="/signup">Sign Up</.button_link>
      <.button_link navigate={~p"/users"} variant="secondary">View Users</.button_link>
  """
  attr :class, :string, default: ""
  attr :full_width, :boolean, default: false
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :rest, :global
  attr :size, :string, default: "md", values: ["sm", "md", "lg"]

  attr :variant, :string,
    default: "primary",
    values: ["primary", "secondary", "danger", "outline", "ghost", "blue"]

  slot :inner_block, required: true

  def button_link(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      patch={@patch}
      class={
        [
          # Base styles
          "tw:inline-flex tw:items-center tw:justify-center tw:gap-2 tw:font-semibold tw:rounded",
          "tw:transition-colors tw:focus:outline-none tw:focus:ring-2 tw:focus:ring-offset-2",
          "tw:cursor-pointer",
          # Size variants
          button_size(@size),
          # Color variants
          button_variant(@variant),
          @full_width && "tw:w-full",
          @class
        ]
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # Size variants
  defp button_size("sm"), do: "tw:h-9 tw:px-3 tw:text-sm"
  defp button_size("md"), do: "tw:h-12 tw:px-4 tw:text-md"
  defp button_size("lg"), do: "tw:h-14 tw:px-6 tw:text-lg"

  # Color variants
  defp button_variant("primary") do
    [
      "tw:bg-primary-600 tw:text-white",
      "tw:hover:bg-primary-700",
      "tw:focus:ring-primary-500"
    ]
  end

  defp button_variant("secondary") do
    [
      "tw:bg-grey-200 tw:text-grey-900",
      "tw:hover:bg-grey-300",
      "tw:focus:ring-grey-400"
    ]
  end

  defp button_variant("danger") do
    [
      "tw:bg-red-600 tw:text-white",
      "tw:hover:bg-red-700",
      "tw:focus:ring-red-500"
    ]
  end

  defp button_variant("outline") do
    [
      "tw:bg-transparent tw:border tw:border-grey-300 tw:text-grey-900",
      "tw:hover:bg-grey-50",
      "tw:focus:ring-grey-400"
    ]
  end

  defp button_variant("ghost") do
    [
      "tw:bg-transparent tw:text-grey-700",
      "tw:hover:bg-grey-100",
      "tw:focus:ring-grey-400"
    ]
  end

  defp button_variant("blue") do
    [
      "tw:bg-blue-700 tw:text-white",
      "tw:hover:bg-blue-800",
      "tw:focus:ring-blue-500"
    ]
  end

  @doc """
  Renders a text link with consistent styling.

  ## Examples

      <.text_link navigate={~p"/login"}>Back to login</.text_link>
      <.text_link href="/signup" variant="primary">Sign up</.text_link>
      <.text_link navigate={~p"/help"} variant="secondary">Learn more</.text_link>
      <.text_link href={~p"/docs/usage"} variant="purple">Mix</.text_link>
  """
  attr :class, :string, default: ""
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :rest, :global

  attr :variant, :string,
    default: "primary",
    values: ["primary", "secondary", "purple"]

  slot :inner_block, required: true

  def text_link(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      patch={@patch}
      class={[
        "tw:transition-colors tw:cursor-pointer",
        "tw:focus:outline-none tw:focus:ring-2 tw:focus:ring-offset-2",
        text_link_variant(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # Text link variants
  defp text_link_variant("primary") do
    "tw:text-blue-600 tw:hover:text-blue-500 tw:focus:ring-blue-500 tw:font-medium"
  end

  defp text_link_variant("secondary") do
    "tw:text-grey-600 tw:hover:text-grey-900 tw:focus:ring-grey-400 tw:font-medium"
  end

  defp text_link_variant("purple") do
    "tw:text-primary-700 tw:hover:text-primary-800 tw:hover:underline tw:focus:ring-primary-500 tw:font-semibold"
  end
end
