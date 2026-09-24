defmodule HexpmWeb.API.UserContactView do
  use HexpmWeb, :view

  def render("show." <> _, %{contact: contact}), do: contact
end
