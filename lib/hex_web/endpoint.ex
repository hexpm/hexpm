defmodule HexWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hex_web

  plug HexWeb.Plugs.Forwarded

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/", from: :hex_web, gzip: true,
    only: ~w(css fonts images js static favicon.ico favicon.png hexsearch.xml robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :json, HexWeb.PlugParser],
    pass: ["*/*"],
    json_decoder: Poison

  plug Plug.MethodOverride
  plug Plug.Head

  plug HexWeb.Router
end
