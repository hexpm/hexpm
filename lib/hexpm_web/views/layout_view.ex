defmodule HexpmWeb.LayoutView do
  use HexpmWeb, :view
  use Phoenix.HTML

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

  def container_class(assigns) do
    Map.get(assigns, :container, "container")
  end

  def search(assigns) do
    Map.get(assigns, :search)
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

  def toaster_notification(flash, alert_type) do
    ~E"""
      <div class="relative top-2">
        <div class="flex flex-row items-center justify-center h-11 max-w-max px-8  mx-auto overflow-hidden bg-white rounded-lg
      shadow bg-white">
          <div class="flex items-center space-x-4">
            <div class="inline-flex rounded-full h-3.5 w-3.5 flex <%= notification_color(alert_type) %>"></div>
            <p class="inline-flex font-medium text-base text-gray-700">
              <%= raw flash %>
            </p>
          </div>
        </div>
      </div>
    """
  end

  defp notification_color(alert_type) do
    cond do
      alert_type in [:raw_error, :error, :raw_warning, :warning] -> "bg-red-600"
      alert_type in [:raw_info, :info, :raw_success, :success] -> "bg-green-600"
      true -> ""
    end
  end
end
