defmodule HexpmWeb.LayoutView do
  use HexpmWeb, :view

  @spec show_search?(map()) :: boolean()
  def show_search?(assigns) do
    Map.get(assigns, :hide_search) != true
  end

  @spec title(map()) :: String.t()
  def title(assigns)
  def title(%{"title" => title}), do: "#{title} | Hex"
  def title(_assigns), do: "Hex"

  @spec description(map) :: String.t()
  def description(assigns)
  def description(%{"description" => description}), do: String.slice(description, 0, 160)
  def description(_assigns), do: "A package manager for the Erlang ecosystem"

  @spec canonical_url(map) :: Phoenix.HTML.safe() | nil
  def canonical_url(assigns)
  def canonical_url(%{canonical_url: url}), do: tag(:link, rel: "canonical", href: url)
  def canonical_url(_assigns), do: nil

  @spec search(map) :: any()
  def search(assigns) do
    Map.get(assigns, :search)
  end

  @spec container_class(map) :: term()
  def container_class(assigns) do
    Map.get(assigns, :container, "container")
  end

  @spec og_tags(map) :: [Phoenix.HTML.safe()]
  def og_tags(assigns) do
    [
      tag(:meta, property: "og:title", content: Map.get(assigns, :title)),
      tag(:meta, property: "og:type", content: "website"),
      tag(:meta, property: "og:url", content: Map.get(assigns, :canonical_url)),
      tag(
        :meta,
        property: "og:image",
        content: url(~p"/images/favicon-160.png")
      ),
      tag(:meta, property: "og:image:width", content: "160"),
      tag(:meta, property: "og:image:height", content: "160"),
      tag(:meta, property: "og:description", content: description(assigns)),
      tag(:meta, property: "og:site_name", content: "Hex")
    ]
  end
end
