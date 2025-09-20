defmodule HexpmWeb.API.OAuthView do
  use HexpmWeb, :view

  def render("device_authorization." <> _, %{device_response: response}) do
    %{
      device_code: response.device_code,
      user_code: response.user_code,
      verification_uri: response.verification_uri,
      verification_uri_complete: response.verification_uri_complete,
      expires_in: response.expires_in,
      interval: response.interval
    }
  end

  def render("token." <> _, %{token_response: response}) do
    response
  end

  def render("error." <> _, %{error_type: error_type, description: description}) do
    %{
      error: to_string(error_type),
      error_description: description
    }
  end
end
