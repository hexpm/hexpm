defmodule HexpmWeb.Components.Tooltip do
  @moduledoc """
  Simple tooltip component that appears on hover using CSS data-tooltip attribute.
  """
  use Phoenix.Component

  @doc """
  Renders a tooltip wrapper using data-tooltip attribute.

  ## Examples

      <.tooltip text="Delete email">
        <button>🗑️</button>
      </.tooltip>
  """
  attr :text, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <span class={["tooltip", @class]} data-tooltip={@text}>
      {render_slot(@inner_block)}
    </span>
    """
  end
end
