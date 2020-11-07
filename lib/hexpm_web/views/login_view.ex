defmodule HexpmWeb.LoginView do
  use HexpmWeb, :view

  def github_login_path, do: Hexpm.OAuthProviders.GitHub.authorize_uri()
end
