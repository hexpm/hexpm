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
      current_user: assigns[:current_user],
      script_src_nonce: assigns[:script_src_nonce],
      style_src_nonce: assigns[:style_src_nonce]
    )
  end

  def render(<<status::binary-3>> <> _, assigns) when status != "all" do
    assigns
    |> Map.take([:message, :errors])
    |> maybe_put_error(assigns[:error])
    |> Map.put(:status, String.to_integer(status))
    |> Map.put_new(:message, message(status))
  end

  defp maybe_put_error(response, error) when is_binary(error),
    do: Map.put(response, :error, error)

  defp maybe_put_error(response, _error), do: response

  # In case no render clause matches or no
  # template is found, let's render it as a 500
  def template_not_found(_template, assigns) do
    render(
      "all.html",
      conn: assigns.conn,
      error: true,
      status: "500",
      message: "Internal server error",
      current_user: assigns[:current_user],
      script_src_nonce: assigns[:script_src_nonce],
      style_src_nonce: assigns[:style_src_nonce]
    )
  end

  def message("400"), do: "Bad request"
  def message("404"), do: "Page not found"
  def message("408"), do: "Request timeout"
  def message("413"), do: "Payload too large"
  def message("415"), do: "Unsupported media type"
  def message("422"), do: "Validation error(s)"

  def message("503") do
    "Hex.pm is temporarily read-only for maintenance. This action is unavailable; " <>
      "please try again in a few minutes."
  end

  def message("500"), do: "Internal server error"
  def message(_), do: nil
end
