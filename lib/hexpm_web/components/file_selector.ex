defmodule HexpmWeb.Components.FileSelector do
  use Phoenix.Component

  import HexpmWeb.Components.Modal
  import HexpmWeb.ViewIcons

  @finder_limit 100

  def filter(files, query) do
    filter_by(files, & &1, query)
  end

  def filter_by(items, path, query) when is_function(path, 1) do
    query = query |> String.trim() |> String.downcase()

    items
    |> Enum.filter(&fuzzy_match?(String.downcase(path.(&1)), query))
    |> Enum.sort_by(&file_score(String.downcase(path.(&1)), query))
    |> Enum.take(@finder_limit)
  end

  attr :id, :string, required: true
  attr :query, :string, required: true
  attr :file_count, :integer, required: true
  attr :filter_event, :string, default: "filter_files"
  attr :title, :string, required: true
  attr :sidebar_label, :string, required: true
  attr :search_label, :string, required: true
  attr :search_placeholder, :string, default: "Search files"
  attr :finder_placeholder, :string, default: "Find a file by path…"
  attr :tree_form_id, :string, default: nil
  attr :tree_query_id, :string, default: nil
  attr :finder_form_id, :string, default: nil
  attr :finder_query_id, :string, default: nil

  slot :tree
  slot :results, required: true

  def file_selector(assigns) do
    assigns =
      assign(assigns,
        tree_form_id: assigns.tree_form_id || "#{assigns.id}-tree-search",
        tree_query_id: assigns.tree_query_id || "#{assigns.id}-tree-query",
        finder_form_id: assigns.finder_form_id || "#{assigns.id}-finder",
        finder_query_id: assigns.finder_query_id || "#{assigns.id}-query"
      )

    ~H"""
    <aside class="hidden min-w-0 lg:block">
      <div class="sticky top-4 overflow-hidden rounded-lg border border-grey-200 bg-white dark:border-grey-700 dark:bg-grey-800">
        <div class="border-b border-grey-200 p-3 dark:border-grey-700">
          <form id={@tree_form_id} phx-change={@filter_event}>
            <label for={@tree_query_id} class="sr-only">{@search_label}</label>
            <div class="relative">
              {icon(:heroicon, "magnifying-glass",
                class:
                  "pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-grey-400"
              )}
              <input
                id={@tree_query_id}
                type="search"
                name="query"
                value={@query}
                phx-debounce="100"
                placeholder={@search_placeholder}
                autocomplete="off"
                class="w-full rounded-lg border border-grey-200 bg-grey-50 py-2 pl-9 pr-3 text-sm text-grey-900 outline-none transition-colors placeholder:text-grey-400 focus:border-primary-500 dark:border-grey-700 dark:bg-grey-900 dark:text-grey-100"
              />
            </div>
          </form>
          <p class="mt-2 text-[10px] font-medium uppercase tracking-wide text-grey-400 dark:text-grey-300">
            {@file_count} {if @file_count == 1, do: "file", else: "files"}
          </p>
        </div>
        <nav
          id={"#{@id}-tree"}
          class="max-h-[70vh] overflow-auto p-2"
          aria-label={@sidebar_label}
        >
          <div :if={@query == "" && @tree != []}>
            {render_slot(@tree, %{modal_id: "#{@id}-modal"})}
          </div>
          <div :if={@query != "" || @tree == []}>
            {render_slot(@results, %{close_modal?: false, modal_id: "#{@id}-modal"})}
          </div>
        </nav>
      </div>
    </aside>

    <.modal id={"#{@id}-modal"} title={@title} max_width="3xl">
      <form id={@finder_form_id} phx-change={@filter_event} class="mb-3">
        <label for={@finder_query_id} class="sr-only">{@search_label}</label>
        <div class="relative">
          {icon(:heroicon, "magnifying-glass",
            class: "pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-grey-400"
          )}
          <input
            id={@finder_query_id}
            type="search"
            name="query"
            value={@query}
            phx-debounce="100"
            placeholder={@finder_placeholder}
            autocomplete="off"
            class="w-full rounded-lg border border-grey-200 bg-grey-50 py-2.5 pl-9 pr-3 font-mono text-sm text-grey-900 outline-none transition-colors placeholder:text-grey-400 focus:border-primary-500 dark:border-grey-700 dark:bg-grey-900 dark:text-grey-100"
          />
        </div>
      </form>

      <nav
        id={"#{@id}-results"}
        class="max-h-[60vh] overflow-auto"
        aria-label={@search_label}
      >
        {render_slot(@results, %{close_modal?: true, modal_id: "#{@id}-modal"})}
      </nav>
    </.modal>
    """
  end

  attr :modal_id, :string, required: true

  def file_selector_buttons(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={show_modal(@modal_id)}
      class="inline-flex items-center gap-2 rounded-lg border border-grey-200 bg-white px-3 py-2 text-sm font-medium text-grey-700 shadow-sm transition-colors hover:border-grey-300 hover:bg-grey-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-grey-700 dark:bg-grey-800 dark:text-grey-100 dark:hover:bg-grey-700 lg:hidden"
    >
      {icon(:heroicon, "folder-open", class: "size-4")} Files
    </button>
    <button
      type="button"
      phx-click={show_modal(@modal_id)}
      class="hidden items-center gap-2 rounded-lg border border-grey-200 bg-white px-3 py-2 text-sm font-medium text-grey-700 shadow-sm transition-colors hover:border-grey-300 hover:bg-grey-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-grey-700 dark:bg-grey-800 dark:text-grey-100 dark:hover:bg-grey-700 lg:inline-flex"
    >
      {icon(:heroicon, "magnifying-glass", class: "size-4")} Find file…
    </button>
    """
  end

  attr :items, :list, required: true
  attr :selected, :any, required: true
  slot :item, required: true

  def file_results(assigns) do
    ~H"""
    <ul class="space-y-1">
      <li :for={item <- @items}>
        {render_slot(@item, %{
          item: item,
          class: result_class(@selected.(item))
        })}
      </li>
    </ul>
    """
  end

  defp result_class(selected?) do
    [
      "flex w-full items-center gap-2 rounded px-2 py-2 text-left font-mono text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-1",
      selected? &&
        "bg-primary-50 font-semibold text-primary-700 dark:bg-grey-700 dark:text-white",
      not selected? &&
        "text-grey-600 hover:bg-grey-100 hover:text-grey-900 dark:text-grey-300 dark:hover:bg-grey-700/60 dark:hover:text-white"
    ]
  end

  defp fuzzy_match?(_file, ""), do: true

  defp fuzzy_match?(file, query) do
    String.contains?(file, query) || subsequence?(String.graphemes(file), String.graphemes(query))
  end

  defp subsequence?(_file, []), do: true
  defp subsequence?([], _query), do: false
  defp subsequence?([character | file], [character | query]), do: subsequence?(file, query)
  defp subsequence?([_character | file], query), do: subsequence?(file, query)

  defp file_score(file, query) do
    cond do
      query == "" -> {0, file}
      file == query -> {0, file}
      String.starts_with?(file, query) -> {1, file}
      String.contains?(file, "/#{query}") -> {2, file}
      String.contains?(file, query) -> {3, file}
      true -> {4, file}
    end
  end
end
