defmodule HexWeb.Email do
  use Behaviour

  defcallback send(String.t, binary, binary) :: term
  defcallback send(String.t, String.t, binary, binary) :: term
  defcallback send(String.t, String.t, binary, binary, String.t, String.t, String.t, Integer.t) :: term
end
