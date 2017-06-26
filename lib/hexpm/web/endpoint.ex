defmodule Hexpm.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :hexpm

  plug Hexpm.Web.Plugs.Forwarded

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/", from: :hexpm, gzip: true,
    only: ~w(css fonts images js),
    only_matching: ~w(favicon robots)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :json, Hexpm.Web.PlugParser],
    pass: ["*/*"],
    json_decoder: Hexpm.Web.Jiffy

  plug Plug.MethodOverride
  plug Plug.Head
  plug Hexpm.Web.Plugs.Vary, ["accept-encoding"]

  plug Plug.Session,
    store: Hexpm.Web.Session,
    key: "_hexpm_key",
    max_age: 60 * 60 * 24 * 30

  plug Hexpm.Web.Router
end
