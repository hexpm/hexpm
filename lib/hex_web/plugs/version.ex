defmodule HexWeb.Plugs.Version do
  import Plug.Connection

  @allowed_versions ["beta"]

  def init(opts), do: opts

  def call(conn, _opts) do
    version = conn.assigns[:version] || "beta"
    if version in @allowed_versions do
      put_resp_header(conn, "x-hex-media-type", "hex." <> version)
    else
      raise Plug.Parsers.UnsupportedMediaTypeError
    end
  end
end
