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
          <th class="px-0 py-3 text-left">Name</th>
          <th class="px-4 py-3 text-left">Status</th>
          <th class="px-4 py-3 text-right">Actions</th>
        </:header>
        <:row>
          <td class="px-0 py-4">John Doe</td>
          <td class="px-4 py-4">Active</td>
          <td class="px-4 py-4 text-right">...</td>
        </:row>
      </.table>
  """
  attr :class, :string, default: ""

  slot :header, required: true, doc: "Table header row with <th> elements"
  slot :row, required: true, doc: "Table body rows - can be used with :for"

  def table(assigns) do
    ~H"""
    <div class={["border-b border-grey-200 mb-6 overflow-x-scroll", @class]}>
      <table class="w-full">
        <thead>
          <tr class="border-b border-grey-200">
            {render_slot(@header)}
          </tr>
        </thead>
        <tbody class="divide-y divide-grey-200">
          {render_slot(@row)}
        </tbody>
      </table>
    </div>
    """
  end
end
