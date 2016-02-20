defmodule HexWeb.Store do
  use Behaviour

  defcallback list_logs(String.t, String.t, String.t) :: [String.t]
  defcallback get_logs(String.t, String.t, String.t) :: binary
  defcallback put_logs(String.t, String.t, String.t, binary) :: term

  defcallback put_registry(binary) :: term
  defcallback put_registry_signature(binary) :: term
  defcallback send_registry(Plug.Conn.t) :: Plug.Conn.t
  defcallback send_registry_signature(Plug.Conn.t) :: Plug.Conn.t

  defcallback put_release(String.t, binary) :: term
  defcallback delete_release(String.t) :: term
  defcallback send_release(Plug.Conn.t, String.t) :: Plug.Conn.t

  defcallback put_docs(String.t, binary) :: term
  defcallback delete_docs(String.t) :: term
  defcallback send_docs(Plug.Conn.t, String.t) :: Plug.Conn.t

  defcallback put_docs_page(String.t, binary, binary) :: term
  defcallback list_docs_pages(String.t) :: [String.t]
  defcallback delete_docs_page(String.t) :: term
  defcallback send_docs_page(Plug.Conn.t, String.t) :: Plug.Conn.t
end
