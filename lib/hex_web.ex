defmodule HexWeb do
  use Application

  def start(_type, _args) do
    opts  = [port: 4000, compress: true]

    if port = System.get_env("PORT") do
      opts = Keyword.put(opts, :port, String.to_integer(port))
    end

    config(opts[:port])
    File.mkdir_p!("tmp")

    router = &HexWeb.Router.call(&1, [])
    Plug.Adapters.Cowboy.http(HexWeb.Plugs.Exception, [router], opts)
    HexWeb.Supervisor.start_link
  end

  defp config(port) do
    if System.get_env("S3_BUCKET") do
      store = HexWeb.Store.S3
    else
      store = HexWeb.Store.Local
    end

    use_ssl = match?("https://" <> _, Application.get_env(:hex_web, :url))

    Application.put_env(:hex_web, :use_ssl, use_ssl)
    Application.put_env(:hex_web, :store, store)
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
