defmodule HexWeb.Store do
  import HexWeb.Utils, only: [defdispatch: 2]

  @type region  :: String.t
  @type bucket  :: String.t
  @type prefix  :: key
  @type key     :: String.t
  @type package :: String.t
  @type version :: String.t
  @type body    :: binary
  @type cdn_key :: String.t

  @callback list_logs(region, bucket, prefix) :: [key]
  @callback get_logs(region, bucket, key) :: body
  @callback put_logs(region, bucket, key, body) :: term

  @callback put_registry(body, body | nil) :: term
  @callback put_registry_signature(body) :: term
  @callback send_registry(Plug.Conn.t) :: Plug.Conn.t
  @callback send_registry_signature(Plug.Conn.t) :: Plug.Conn.t

  @callback put_release(package, version, body) :: term
  @callback delete_release(key) :: term
  @callback send_release(Plug.Conn.t, key) :: Plug.Conn.t

  @callback put_docs(key, body) :: term
  @callback delete_docs(key) :: term
  @callback send_docs(Plug.Conn.t, key) :: Plug.Conn.t

  @callback put_docs_file(key, body) :: term
  @callback put_docs_page(key, cdn_key, body) :: term
  @callback list_docs_pages(prefix) :: [key]
  @callback delete_docs_page(key) :: term
  @callback send_docs_page(Plug.Conn.t, key) :: Plug.Conn.t

  defdispatch list_logs(region, bucket, prefix),   to: impl
  defdispatch get_logs(region, bucket, key),       to: impl
  defdispatch put_logs(region, bucket, key, body), to: impl
  defdispatch put_registry(body, signature),       to: impl
  defdispatch put_registry_signature(body),        to: impl
  defdispatch send_registry(conn),                 to: impl
  defdispatch send_registry_signature(conn),       to: impl
  defdispatch put_release(package, version, body), to: impl
  defdispatch delete_release(key),                 to: impl
  defdispatch send_release(conn, key),             to: impl
  defdispatch put_docs(key, body),                 to: impl
  defdispatch delete_docs(key),                    to: impl
  defdispatch send_docs(conn, key),                to: impl
  defdispatch put_docs_file(key, body),            to: impl
  defdispatch put_docs_page(key, cdn_key, body),   to: impl
  defdispatch list_docs_pages(prefix),             to: impl
  defdispatch delete_docs_page(key),               to: impl
  defdispatch send_docs_page(conn, key),           to: impl

  defp impl, do: Application.get_env(:hex_web, :store_impl)
end
