defmodule HexpmWeb.Endpoint do
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
    only: ~w(css images js),
    only_matching: ~w(favicon robots)

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
  plug Logster.Plugs.Logger, excludes: [:params]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json, HexpmWeb.PlugParser],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug HexpmWeb.Plugs.Vary, ["accept-encoding"]

  plug Plug.Session, @session_options

  if Mix.env() == :prod do
    plug Plug.SSL, rewrite_on: [:x_forwarded_proto]
  end

  plug HexpmWeb.Router

  def init(_key, config) do
    if config[:load_from_system_env] do
      port = Application.get_env(:hexpm, :port)

      case Integer.parse(port) do
        {_int, ""} ->
          host = Application.get_env(:hexpm, :host)
          secret_key_base = Application.get_env(:hexpm, :secret_key_base)
          live_view_signing_salt = Application.get_env(:hexpm, :live_view_signing_salt)

          config = put_in(config[:http][:port], port)
          config = put_in(config[:url][:host], host)
          config = put_in(config[:secret_key_base], secret_key_base)
          config = put_in(config[:live_view][:signing_salt], live_view_signing_salt)
          config = put_in(config[:check_origin], ["//#{host}"])

          {:ok, config}

        :error ->
          {:ok, config}
      end
    else
      {:ok, config}
    end
  end
end
