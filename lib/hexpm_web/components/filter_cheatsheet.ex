defmodule HexpmWeb.Components.FilterCheatsheet do
  use Phoenix.Component

  import HexpmWeb.Components.Modal

  @filters [
    {"name:", "Match package (or repo/package) name", "name:phoenix"},
    {"description:", "Full-text search of package descriptions", "description:auth"},
    {"depends:", "Packages depending on a given package", "depends:ecto"},
    {"build_tool:", "Filter by build tool", "build_tool:mix"},
    {"updated_after:", "Packages updated after an ISO8601 datetime",
     "updated_after:2025-01-01T00:00:00Z"},
    {"extra:", "Match custom metadata (key,value). Nested keys are separated by commas",
     "extra:license,MIT"}
  ]

  attr :id, :string, required: true

  def cheatsheet(assigns) do
    assigns = assign(assigns, :filters, @filters)

    ~H"""
    <.modal id={@id} title="Search filters">
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-3">
        Type any of these into the search box. They can be combined with free text
        which searches package names and descriptions.
      </p>
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b">
            <th class="py-1 pr-3">Operator</th>
            <th class="py-1 pr-3">Description</th>
            <th class="py-1">Example</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{op, desc, example} <- @filters} class="border-b last:border-b-0">
            <td class="py-1 pr-3 font-mono">{op}</td>
            <td class="py-1 pr-3">{desc}</td>
            <td class="py-1 font-mono">{example}</td>
          </tr>
        </tbody>
      </table>
    </.modal>
    """
  end
end
