defmodule HexWeb.ErrorView do
  use HexWeb.Web, :view

  def render(<<status::binary-3>> <> ".html", _assigns) when status != "all" do
    render "all.html",
           status: status,
           message: message(status)
  end

  def render(<<status::binary-3>> <> _, assigns) when status != "all" do
    assigns
    |> Map.take([:message, :errors])
    |> Map.put(:status, String.to_integer(status))
    |> Map.put_new(:message, message(status))
  end

  # In case no render clause matches or no
  # template is found, let's render it as 500
  def template_not_found(_template, _assigns) do
    render "all.html",
           status: "500",
           message: "Internal server error"
  end

  defp message("400"), do: "Bad request"
  defp message("404"), do: "Page not found"
  defp message("408"), do: "Request timeout"
  defp message("413"), do: "Payload too large"
  defp message("415"), do: "Unsupported media type"
  defp message("422"), do: "Validation error(s)"
  defp message("500"), do: "Internal server error"
  defp message(_),     do: nil
end
