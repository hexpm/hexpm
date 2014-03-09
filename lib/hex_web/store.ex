defmodule HexWeb.Store do
  use Behaviour

  defcallback upload_registry(file :: String.t) :: term
  defcallback registry(Plug.Conn.t) :: Plug.Conn.t
end
