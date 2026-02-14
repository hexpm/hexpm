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
  attr :variant, :string, default: "default", values: ~w(default green purple)
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "tw:inline-flex tw:items-center tw:justify-center tw:px-3 tw:py-1 tw:rounded tw:text-xs tw:font-medium tw:leading-3",
      badge_variant(@variant)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_variant("default"), do: "tw:bg-grey-200 tw:text-grey-700"
  defp badge_variant("green"), do: "tw:bg-green-100 tw:text-green-700"
  defp badge_variant("purple"), do: "tw:bg-purple-100 tw:text-purple-700"
end
