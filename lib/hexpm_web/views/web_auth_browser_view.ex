defmodule HexpmWeb.WebAuthBrowserView do
  use HexpmWeb, :view

  def error_tag(error) do
    if error do
      content_tag(:span, error, class: "form-error alert alert-danger", role: "alert")
    end
  end
end
