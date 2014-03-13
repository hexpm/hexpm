defmodule HexWeb.Store do
  use Behaviour

  defcallback upload_registry(binary) :: term
  defcallback registry(Plug.Conn.t) :: Plug.Conn.t

  defcallback upload_tar(String.t, binary) :: term
  defcallback tar(Plug.Conn.t, String.t) :: Plug.Conn.t
end
