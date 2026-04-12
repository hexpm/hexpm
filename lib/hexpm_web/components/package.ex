defmodule HexpmWeb.Components.Package do
  @moduledoc """
  Reusable components for package pages.
  """
  use Phoenix.Component
  import HexpmWeb.Components.Input, only: [select_input: 1]

  @doc """
  Renders a sort dropdown for package lists.

  ## Examples

      <.sort_selector sort={@sort} />
  """
  attr :sort, :atom, required: true

  def sort_selector(assigns) do
    assigns =
      assign(assigns, :sort_options, [
        {"Name", "name"},
        {"Total downloads", "total_downloads"},
        {"Recent downloads", "recent_downloads"},
        {"Recently created", "inserted_at"},
        {"Recently updated", "updated_at"}
      ])

    ~H"""
    <form phx-change="sort_change">
      <.select_input
        id="sort-select"
        name="sort"
        label="Sort by"
        options={@sort_options}
        value={to_string(@sort)}
      />
    </form>
    """
  end
end
