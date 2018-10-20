defmodule HexpmWeb.LayoutView do
  use HexpmWeb, :view

  def show_search?(assigns) do
    Map.get(assigns, :hide_search) != true
  end

  def title(assigns) do
    if title = Map.get(assigns, :title) do
      "#{title} | Hex"
    else
      "Hex"
    end
  end

  def description(assigns) do
    if description = Map.get(assigns, :description) do
      String.slice(description, 0, 160)
    else
      "A package manager for the Erlang ecosystem"
    end
  end

  def canonical_url(assigns) do
    if url = Map.get(assigns, :canonical_url) do
      tag(:link, rel: "canonical", href: url)
    else
      nil
    end
  end

  def search(assigns) do
    Map.get(assigns, :search)
  end

  def container_class(assigns) do
    Map.get(assigns, :container, "container")
  end

  def og_tags(assigns) do
    [
      tag(:meta, property: "og:title", content: Map.get(assigns, :title)),
      tag(:meta, property: "og:type", content: "website"),
      tag(:meta, property: "og:url", content: Map.get(assigns, :canonical_url)),
      tag(
        :meta,
        property: "og:image",
        content: Routes.static_url(HexpmWeb.Endpoint, "/images/favicon-160.png")
      ),
      tag(:meta, property: "og:image:width", content: "160"),
      tag(:meta, property: "og:image:height", content: "160"),
      tag(:meta, property: "og:description", content: description(assigns)),
      tag(:meta, property: "og:site_name", content: "Hex")
    ]
  end
end
