defmodule HexpmWeb.Components.Table do
  @moduledoc """
  Reusable table component for dashboard pages.
  """
  use Phoenix.Component

  @doc """
  Renders a table with header and body slots.

  ## Examples

      <.table>
        <:header>
          <th class="tw:px-0 tw:py-3 tw:text-left">Name</th>
          <th class="tw:px-4 tw:py-3 tw:text-left">Status</th>
          <th class="tw:px-4 tw:py-3 tw:text-right">Actions</th>
        </:header>
        <:row>
          <td class="tw:px-0 tw:py-4">John Doe</td>
          <td class="tw:px-4 tw:py-4">Active</td>
          <td class="tw:px-4 tw:py-4 tw:text-right">...</td>
        </:row>
      </.table>
  """
  attr :class, :string, default: ""

  slot :header, required: true, doc: "Table header row with <th> elements"
  slot :row, required: true, doc: "Table body rows - can be used with :for"

  def table(assigns) do
    ~H"""
    <div class={["tw:border-b tw:border-grey-200 tw:mb-6", @class]}>
      <table class="tw:w-full">
        <thead>
          <tr class="tw:border-b tw:border-grey-200">
            {render_slot(@header)}
          </tr>
        </thead>
        <tbody class="tw:divide-y tw:divide-grey-200">
          {render_slot(@row)}
        </tbody>
      </table>
    </div>
    """
  end
end
