defmodule HexpmWeb.API.OIDCView do
  use HexpmWeb, :view

  def render("audience." <> _, %{audience: audience}) do
    %{audience: audience}
  end

  def render("token." <> _, %{token: token}) do
    expires_in = DateTime.diff(token.expires_at, DateTime.utc_now())

    %{
      token: token.access_token,
      token_type: token.token_type || "bearer",
      expires_in: max(expires_in, 0),
      expires_at: DateTime.to_iso8601(token.expires_at)
    }
  end

  def render("error." <> _, %{error_type: error_type, description: description}) do
    %{
      error: to_string(error_type),
      error_description: description
    }
  end
end
