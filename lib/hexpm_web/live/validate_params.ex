defmodule HexpmWeb.Live.ValidateParams do
  @moduledoc """
  The LiveView side of `HexpmWeb.Plugs.ValidateParams`. Params a connected
  socket receives, at mount, on a patch, or with an event, come over the
  websocket and never pass through the endpoint, so the same text check runs
  here.

  A browser never sends these: the page's own request would have been refused
  by the plug before the socket connected. So a refused mount or patch is sent
  to the home page rather than answered, and a refused event is dropped.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  def on_mount(:default, params, _session, socket) do
    if Hexpm.Utils.storable_text?(params) do
      socket =
        socket
        |> attach_params_hook(params)
        |> attach_hook(:validate_event, :handle_event, fn _event, params, socket ->
          if Hexpm.Utils.storable_text?(params), do: {:cont, socket}, else: {:halt, socket}
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  # A view embedded with live_render takes no params and can't carry a
  # handle_params hook.
  defp attach_params_hook(socket, :not_mounted_at_router), do: socket

  defp attach_params_hook(socket, _params) do
    attach_hook(socket, :validate_params, :handle_params, fn params, _uri, socket ->
      if Hexpm.Utils.storable_text?(params),
        do: {:cont, socket},
        else: {:halt, redirect(socket, to: "/")}
    end)
  end
end
