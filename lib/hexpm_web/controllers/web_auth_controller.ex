defmodule HexpmWeb.WebAuthController do
  use HexpmWeb, :controller
  @moduledoc false

  # Controller for Web Auth, a means of authenticating the cli from the website

  plug :requires_login when action == :show

  # step one of device flow
  def code(conn, params) do
    case Hexpm.WebAuth.get_code(params) do
      {:error, "invalid scope"} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid scope"})

      {:error, "invalid parameters"} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "invalid parameters"})

      response ->
        conn
        |> put_status(:ok)
        |> json(response)
    end
  end

  def show(conn, _) do
    render(conn, "show.html")
  end

  def submit(conn, params) do
    params = Map.merge(params, %{audit: conn})
    _ = IO.inspect(params["user_id"], label: "UID: ")
    _ = IO.inspect(conn.assigns.organization, label: "Conn OID: ")
    _ = IO.inspect(conn.assigns.current_user, label: "Conn UID")

    case Hexpm.WebAuth.submit_code(params) do
      {:error, "not found"} ->
        "foo"

      :ok ->
        redirect(conn, to: Routes.web_auth_path(conn, :sucess))
    end
  end

  def sucess(conn, _) do
    json(conn, %{foo: "foo"})
  end

  def access_token(conn, params) do
    json(conn, params)
  end
end
