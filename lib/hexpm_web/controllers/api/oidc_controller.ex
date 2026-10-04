defmodule HexpmWeb.API.OIDCController do
  use HexpmWeb, :controller

  alias Hexpm.TrustedPublishers

  plug :feature_enabled

  @doc """
  Returns the OIDC audience Hex expects for trusted publisher tokens.
  """
  def audience(conn, _params) do
    render(conn, :audience, audience: TrustedPublishers.audience())
  end

  defp feature_enabled(conn, _opts) do
    if TrustedPublishers.enabled?() do
      conn
    else
      conn
      |> put_status(404)
      |> render(:error, error_type: :not_found, description: "Not found")
      |> halt()
    end
  end
end
