defmodule HexpmWeb.WebAuthView do
  use HexpmWeb, :view

  def render("code.json", reponse) do
    Map.take(reponse, [:device_code, :user_code])
  end

  def render("access.json", %{write_key: write_key, read_key: read_key}) do
    %{
      write_key: Routes.api_key_url(Endpoint, :show, write_key),
      read_key: Routes.api_key_url(Endpoint, :show, read_key)
    }
  end

  def error_tag(field, error) do
    content_tag(:span, error, class: "form-error")
  end
end
