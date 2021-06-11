defmodule HexpmWeb.WebAuthController do
  use HexpmWeb, :controller
  @moduledoc false

  # Controller for Web Auth, a mode of authenticating the cli from the website

  @scopes ["write", "read"]

  # step one of device flow
  def code(conn, params) do
    case params do
      %{"scope" => scope} when scope in @scopes ->
        conn
        |> put_status(:ok)
        |> json(Hexpm.WebAuth.get_code(scope))

      %{"scope" => _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid scope"})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "invalid parameters"})
    end
  end

  def show(conn, params) do
    json(conn, params)
  end

  def access_token(conn, params) do
    json(conn, params)
  end
end
