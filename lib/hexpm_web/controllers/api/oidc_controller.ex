defmodule HexpmWeb.API.OIDCController do
  use HexpmWeb, :controller

  alias Hexpm.WorkloadIdentities

  plug :feature_enabled

  @doc """
  Returns the OIDC audience Hex expects for workload identity tokens.
  """
  def audience(conn, _params) do
    render(conn, :audience, audience: WorkloadIdentities.audience())
  end

  defp feature_enabled(conn, _opts) do
    if WorkloadIdentities.enabled?() do
      conn
    else
      conn
      |> put_status(404)
      |> render(:error, error_type: :not_found, description: "Not found")
      |> halt()
    end
  end
end
