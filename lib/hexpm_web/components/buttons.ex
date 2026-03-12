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
      <.button variant="outline" class="w-full">Sign Up</.button>

      <.button disabled>Disabled</.button>
      <.button loading>Processing...</.button>
  """
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false
  attr :full_width, :boolean, default: false
  attr :loading, :boolean, default: false

  # Global attributes:
  # - phx-click, phx-target, phx-value-id: LiveView event handling
  # - form: Associate button with a form element
  # - onclick: For submitting hidden forms (e.g., confirmation modals with CSRF protection)
  # - data-input-id: Legacy jQuery integration for package pages
  # - id: Required for phx-hook elements and form submissions
  attr :rest, :global,
    include:
      ~w(phx-click phx-target phx-value-id form onclick data-input-id id phx-hook data-copy-target data-print-target data-download-target)

  attr :size, :string, default: "md", values: ["sm", "md", "lg"]
  attr :type, :string, default: "button", values: ["button", "submit", "reset"]

  attr :variant, :string,
    default: "primary",
    values: ["primary", "secondary", "danger", "danger-outline", "outline", "ghost", "blue"]

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled || @loading}
      class={
        [
          # Base styles
          "inline-flex items-center justify-center gap-2 font-semibold rounded",
          "transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2",
          "cursor-pointer",
          # Size variants
          button_size(@size),
          # Color variants
          button_variant(@variant),
          # Disabled state - use CSS pseudo-class for dynamic changes
          "disabled:opacity-50 disabled:cursor-not-allowed",
          @full_width && "w-full",
          @class
        ]
      }
      {@rest}
    >
      <span :if={@loading} class="animate-spin">
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
    values: ["primary", "secondary", "danger", "danger-outline", "outline", "ghost", "blue"]

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
          "inline-flex items-center justify-center gap-2 font-semibold rounded",
          "transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2",
          "cursor-pointer",
          # Size variants
          button_size(@size),
          # Color variants
          button_variant(@variant),
          @full_width && "w-full",
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
  defp button_size("sm"), do: "h-9 px-3 text-sm"
  defp button_size("md"), do: "h-12 px-4 text-md"
  defp button_size("lg"), do: "h-14 px-6 text-lg"

  # Color variants
  defp button_variant("primary") do
    [
      "bg-primary-600 text-white",
      "hover:bg-primary-700",
      "focus:ring-primary-500"
    ]
  end

  defp button_variant("secondary") do
    [
      "bg-grey-200 text-grey-900",
      "hover:bg-grey-300",
      "focus:ring-grey-400"
    ]
  end

  defp button_variant("danger") do
    [
      "bg-red-600 text-white",
      "hover:bg-red-700",
      "focus:ring-red-500"
    ]
  end

  defp button_variant("danger-outline") do
    [
      "bg-white border border-red-300 text-red-600",
      "hover:bg-red-50",
      "focus:ring-red-500"
    ]
  end

  defp button_variant("outline") do
    [
      "bg-transparent border border-grey-300 text-grey-900",
      "hover:bg-grey-50",
      "focus:ring-grey-400"
    ]
  end

  defp button_variant("ghost") do
    [
      "bg-transparent text-grey-700",
      "hover:bg-grey-100",
      "focus:ring-grey-400"
    ]
  end

  defp button_variant("blue") do
    [
      "bg-blue-700 text-white",
      "hover:bg-blue-800",
      "focus:ring-blue-500"
    ]
  end

  @doc """
  Renders an icon-only button with hover states.

  ## Examples

      <.icon_button icon="trash" phx-click="delete" />
      <.icon_button icon="pencil" variant="primary" />
      <.icon_button icon="trash" variant="danger" aria-label="Delete" />
  """
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false
  attr :icon, :string, required: true
  attr :size, :integer, default: 16
  attr :type, :string, default: "button", values: ["button", "submit", "reset"]
  attr :variant, :string, default: "default", values: ["default", "danger", "primary"]
  attr :rest, :global, include: ~w(phx-click phx-target phx-value-id id aria-label onclick)

  def icon_button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[
        "p-2 rounded transition-colors cursor-pointer",
        icon_button_variant(@variant),
        "disabled:opacity-50 disabled:cursor-not-allowed",
        @class
      ]}
      {@rest}
    >
      {icon(:heroicon, @icon, width: @size, height: @size)}
    </button>
    """
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
        "transition-colors cursor-pointer",
        "focus:outline-none focus:ring-2 focus:ring-offset-2",
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
    "text-blue-600 hover:text-blue-500 focus:ring-blue-500 font-medium"
  end

  defp text_link_variant("secondary") do
    "text-grey-600 hover:text-grey-900 focus:ring-grey-400 font-medium"
  end

  defp text_link_variant("purple") do
    "text-primary-700 hover:text-primary-800 hover:underline focus:ring-primary-500 font-semibold"
  end

  # Icon button variants
  defp icon_button_variant("default") do
    "text-grey-400 hover:text-grey-700 hover:bg-grey-100 disabled:hover:text-grey-400 disabled:hover:bg-transparent"
  end

  defp icon_button_variant("danger") do
    "text-grey-400 hover:text-red-600 hover:bg-red-50 disabled:hover:text-grey-400 disabled:hover:bg-transparent"
  end

  defp icon_button_variant("primary") do
    "text-grey-400 hover:text-primary-600 hover:bg-primary-50 disabled:hover:text-grey-400 disabled:hover:bg-transparent"
  end
end
