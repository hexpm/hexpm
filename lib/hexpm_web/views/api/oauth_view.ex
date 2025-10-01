defmodule HexpmWeb.API.OAuthView do
  use HexpmWeb, :view

  def render("device_authorization." <> _, %{device_response: response}) do
    expires_in = DateTime.diff(response.expires_at, DateTime.utc_now())

    %{
      device_code: response.device_code,
      user_code: response.user_code,
      verification_uri: response.verification_uri,
      verification_uri_complete: response.verification_uri_complete,
      expires_in: max(expires_in, 0),
      interval: response.interval
    }
  end

  def render("token." <> _, %{token: token}) do
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

  def render("error." <> _, %{error_type: error_type, description: description}) do
    %{
      error: to_string(error_type),
      error_description: description
    }
  end
end
