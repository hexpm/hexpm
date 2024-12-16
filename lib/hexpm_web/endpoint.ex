defmodule HexpmWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :hexpm

  plug HexpmWeb.Plugs.Forwarded

  @session_options [
    signing_salt: "NOcCmerj",
    store: HexpmWeb.Session,
    key: "_hexpm_key",
    max_age: 60 * 60 * 24 * 30
  ]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :hexpm,
    gzip: true,
    only: HexpmWeb.static_paths()

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :hexpm
  end

  plug HexpmWeb.Plugs.Status

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Logster.Plugs.ChangeLogLevel, to: :info
  plug Logster.Plugs.Logger, excludes: [:params]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json, HexpmWeb.PlugParser],
    pass: ["*/*"],
    json_decoder: Jason

  plug Sentry.PlugContext
  plug Plug.MethodOverride
  plug Plug.Head
  plug HexpmWeb.Plugs.Vary, ["accept-encoding"]

  plug Plug.Session, @session_options

  if Mix.env() == :prod do
    plug Plug.SSL, rewrite_on: [:x_forwarded_proto]
  end

  plug HexpmWeb.Router
end
