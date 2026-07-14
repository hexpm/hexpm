defmodule Hexpm.Preview.Sitemaps do
  require EEx

  package_template = ~S"""
  <?xml version="1.0" encoding="utf-8"?>
  <urlset
      xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">
  <%= for file <- files do %>
    <url>
      <loc><%= xml_escape(preview_url <> "/preview/" <> package <> "/show/" <> encode_path(file)) %></loc>
      <lastmod><%= format_datetime(updated_at) %></lastmod>
      <changefreq>daily</changefreq>
      <priority>0.8</priority>
    </url>
  <% end %>
  </urlset>
  """

  EEx.function_from_string(:def, :render_package, package_template, [
    :preview_url,
    :package,
    :files,
    :updated_at
  ])

  index_template = ~S"""
  <?xml version="1.0" encoding="utf-8"?>
  <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <%= for {package, updated_at} <- packages do %>
    <sitemap>
      <loc><%= xml_escape(preview_url <> "/preview/" <> package <> "/sitemap.xml") %></loc>
      <lastmod><%= format_datetime(updated_at) %></lastmod>
    </sitemap>
  <% end %>
  </sitemapindex>
  """

  EEx.function_from_string(:def, :render_index, index_template, [:preview_url, :packages])

  defp format_datetime(datetime) do
    datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp encode_path(path) do
    URI.encode(path, &(&1 == ?/ or URI.char_unreserved?(&1)))
  end

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
