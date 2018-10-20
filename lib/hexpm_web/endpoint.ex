defmodule HexpmWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hexpm

  plug HexpmWeb.Plugs.Forwarded

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :hexpm,
    gzip: true,
    only: ~w(css fonts images js),
    only_matching: ~w(favicon robots)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :json, HexpmWeb.PlugParser],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug HexpmWeb.Plugs.Vary, ["accept-encoding"]

  plug Plug.Session,
    store: HexpmWeb.Session,
    key: "_hexpm_key",
    max_age: 60 * 60 * 24 * 30

  plug HexpmWeb.Plugs.Status

  if Mix.env() == :prod do
    plug Plug.SSL, rewrite_on: [:x_forwarded_proto]
  end

  plug HexpmWeb.Router

  def init(_key, config) do
    if config[:load_from_system_env] do
      port = System.get_env("HEXPM_PORT")

      case Integer.parse(port) do
        {_int, ""} ->
          host = System.get_env("HEXPM_HOST")
          secret_key_base = System.get_env("HEXPM_SECRET_KEY_BASE")
          config = put_in(config[:http][:port], port)
          config = put_in(config[:url][:host], host)
          config = put_in(config[:secret_key_base], secret_key_base)
          {:ok, config}

        :error ->
          {:ok, config}
      end
    else
      {:ok, config}
    end
  end
end
