defmodule HexpmWeb.Components.Badge do
  @moduledoc """
  Reusable badge component for status indicators.
  """
  use Phoenix.Component

  @doc """
  Renders a badge with text.

  ## Examples

      <.badge>Primary</.badge>
      <.badge>Public</.badge>
      <.badge>Unverified</.badge>
  """
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class="tw:inline-flex tw:items-center tw:justify-center tw:px-3 tw:py-1 tw:rounded tw:text-xs tw:font-medium tw:bg-grey-100 tw:text-grey-700">
      {render_slot(@inner_block)}
    </span>
    """
  end
end
