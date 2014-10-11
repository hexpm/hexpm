defmodule HexWeb.Email do
  use Behaviour

  defcallback send(String.t, String.t, String.t) :: term
end
