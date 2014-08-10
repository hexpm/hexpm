defmodule HexWeb.Web.HTML.Helpers do
  def paginate(page, count, opts) do
    per_page  = opts[:items_per_page]
    max_links = opts[:page_links] # Needs to be odd number

    all_pages    = div(count - 1, per_page) + 1
    middle_links = div(max_links, 2) + 1

    page_links =
      cond do
        page < middle_links ->
          Enum.take(1..max_links, all_pages)
        page > all_pages - middle_links ->
          start =
            if all_pages > middle_links + 1 do
              all_pages - (middle_links + 1)
            else
              1
            end
          Enum.to_list(start..all_pages)
        true ->
          Enum.to_list(page-2..page+2)
      end

    if page != 1,         do: prev = true
    if page != all_pages, do: next = true

    %{prev: prev || false,
      next: next || false,
      page_links: page_links}
  end

  def present?(""),  do: false
  def present?(nil), do: false
  def present?(_),   do: true
end
