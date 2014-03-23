defmodule HexWeb.Store do
  use Behaviour

  defcallback list(String.t) :: [String.t]
  defcallback get(String.t) :: binary
  defcallback put(String.t, binary) :: term

  defcallback put_registry(binary) :: term
  defcallback registry(Plug.Conn.t) :: Plug.Conn.t

  defcallback put_tar(String.t, binary) :: term
  defcallback delete_tar(String.t) :: term
  defcallback tar(Plug.Conn.t, String.t) :: Plug.Conn.t
end
