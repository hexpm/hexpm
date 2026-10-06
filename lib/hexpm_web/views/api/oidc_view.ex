defmodule HexpmWeb.API.OIDCView do
  use HexpmWeb, :view

  def render("audience." <> _, %{audience: audience}) do
    %{audience: audience}
  end

  def render("error." <> _, %{error_type: error_type, description: description}) do
    %{
      error: to_string(error_type),
      error_description: description
    }
  end
end
