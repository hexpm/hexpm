defmodule HexpmWeb.Live.StaticReload do
  @moduledoc """
  on_mount callback that forces a full page load when the connecting client's
  tracked static assets are stale. A client that reconnects across a deploy
  still runs the CSS and JS it loaded before the deploy, so markup rendered by
  the new server would render unstyled and new hooks would be missing.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket) do
      {:cont,
       attach_hook(socket, :static_reload, :handle_params, fn _params, uri, socket ->
         {:halt, redirect(socket, to: path_with_query(URI.parse(uri)))}
       end)}
    else
      {:cont, socket}
    end
  end

  defp path_with_query(%URI{path: path, query: nil}), do: path
  defp path_with_query(%URI{path: path, query: query}), do: path <> "?" <> query
end
