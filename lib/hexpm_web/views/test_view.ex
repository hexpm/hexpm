defmodule HexpmWeb.TestView do
  use HexpmWeb, :view

  def render("oauth_token." <> _, %{token: token}) do
    expires_in = DateTime.diff(token.expires_at, DateTime.utc_now())

    response = %{
      access_token: token.access_token,
      token_type: token.token_type,
      expires_in: max(expires_in, 0),
      scope: Enum.join(token.scopes, " ")
    }

    if token.refresh_token,
      do: Map.put(response, :refresh_token, token.refresh_token),
      else: response
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
