defmodule HexpmWeb.TestView do
  use HexpmWeb, :view

  def render("oauth_token." <> _, %{token_response: response}) do
    response
  end

  def render("oauth_device_authorize." <> _, %{response: response}) do
    response
  end

  def render("oauth_device_pending." <> _, %{response: response}) do
    response
  end

  def render("error." <> _, %{error: error}) do
    error
  end
end
