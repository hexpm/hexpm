require Logger

defmodule HexWeb do
  use Application

  def start(_type, _args) do
    opts  = [port: 4000, compress: true, linger: {true, 10}]

    if port = System.get_env("PORT") do
      opts = Keyword.put(opts, :port, String.to_integer(port))
    end

    config(opts[:port])
    File.mkdir_p!("tmp")

    Logger.info "Starting Cowboy on port #{opts[:port]}"
    Plug.Adapters.Cowboy.http(HexWeb.Router, [], opts)
    HexWeb.Supervisor.start_link
  end

  def request_read_opts do
    # Max filesize: ~10mb
    # Min upload: ~10kb/s
    [ length: 10_000_000,
      read_length: 100_000,
      read_timeout: 10_000 ]
  end

  def request_read_fast_opts do
    # Max filesize: ~10mb
    # Min upload: ~10kb/s
    [ length: 10_000_000,
      read_length: 10_000,
      read_timeout: 1_000 ]
  end

  defp config(port) do
    if System.get_env("HEX_S3_BUCKET") do
      store = HexWeb.Store.S3
    else
      store = HexWeb.Store.Local
    end

    if System.get_env("HEX_SES_USERNAME") do
      email = HexWeb.Email.SES
    else
      email = HexWeb.Email.Local
    end

    use_ssl = match?("https://" <> _, Application.get_env(:hex_web, :url))

    Application.put_env(:hex_web, :use_ssl, use_ssl)
    Application.put_env(:hex_web, :store, store)
    Application.put_env(:hex_web, :email, email)
    Application.put_env(:hex_web, :tmp, Path.expand("tmp"))
    Application.put_env(:hex_web, :port, port)
  end

  defprotocol Render do
    @moduledoc """
    Render entities to something that can be showed publicly.
    Used, for example, when converting entities to JSON responses.
    """

    @spec render(term) :: Dict.t
    def render(entity)
  end
end
