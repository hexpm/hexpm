defmodule HexpmWeb.Components.Badge do
  @moduledoc """
  Reusable badge component for status indicators.
  """
  use Phoenix.Component

  @doc """
  Renders a badge with text.

  ## Examples

      <.badge>Primary</.badge>
      <.badge variant="green">API</.badge>
      <.badge variant="purple">REPOS</.badge>
  """
  attr :variant, :string, default: "default", values: ~w(default green purple blue red yellow)
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center justify-center px-3 py-1 rounded text-xs font-medium leading-3",
      badge_variant(@variant)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_variant("default"), do: "bg-grey-200 text-grey-700"
  defp badge_variant("blue"), do: "bg-blue-100 text-blue-700"
  defp badge_variant("green"), do: "bg-green-100 text-green-700"
  defp badge_variant("purple"), do: "bg-purple-100 text-purple-700"
  defp badge_variant("red"), do: "bg-red-100 text-red-700"
  defp badge_variant("yellow"), do: "bg-yellow-100 text-yellow-700"
end
