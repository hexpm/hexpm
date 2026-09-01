defmodule HexpmWeb.API.SSOAuthorizationView do
  use HexpmWeb, :view

  def render("show." <> _, %{authorization: authorization}) do
    expires_in = DateTime.diff(authorization.expires_at, DateTime.utc_now())

    %{
      verification_uri: url(~p"/sso/authorize?#{[code: authorization.raw_code]}"),
      expires_in: max(expires_in, 0)
    }
  end
end
