defmodule HexpmWeb.ErrorView do
  use HexpmWeb, :view

  def render(<<status::binary-3>> <> ".html", assigns) when status != "all" do
    render(
      "all.html",
      conn: assigns.conn,
      error: true,
      status: status,
      message: message(status),
      container: "container error-view",
      current_user: assigns[:current_user]
    )
  end

  def render(<<status::binary-3>> <> _, assigns) when status != "all" do
    assigns
    |> Map.take([:message, :errors])
    |> Map.put(:status, String.to_integer(status))
    |> Map.put_new(:message, message(status))
  end

  # In case no render clause matches or no
  # template is found, let's render it as a 500
  def template_not_found(_template, assigns) do
    render(
      "all.html",
      conn: assigns.conn,
      error: true,
      status: "500",
      message: "Internal server error",
      current_user: assigns[:current_user]
    )
  end

  defp message("400"), do: "Bad request"
  defp message("404"), do: "Page not found"
  defp message("408"), do: "Request timeout"
  defp message("413"), do: "Payload too large"
  defp message("415"), do: "Unsupported media type"
  defp message("422"), do: "Validation error(s)"
  defp message("500"), do: "Internal server error"
  defp message(_), do: nil
end
