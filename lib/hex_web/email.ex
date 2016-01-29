defmodule HexWeb.Email do
  use Behaviour

  defcallback send(String.t, String.t, Phoenix.HTML.safe) :: term
end
