defmodule HexpmWeb.WebAuthController do
  use HexpmWeb, :controller
  @moduledoc false

  plug :requires_login when action == :show

  def submit(conn, params)

  def submit(conn, %{"user_code" => user_code}) do
    audit = audit_data(conn)
    user = conn.assigns.current_user

    case Hexpm.Accounts.WebAuth.submit(user, user_code, audit) do
      {:ok, _request} ->
        conn
        |> put_status(:found)
        |> redirect(external: Routes.web_auth_url(conn, :success))

      {:error, msg} when msg == "invalid user code" ->
        conn
        |> put_status(:bad_request)
        |> render_show(msg)

      {:error, msg} ->
        conn
        |> put_status(:internal_server_error)
        |> render_show(msg)
    end
  end

  def show(conn, _), do: render_show(conn, nil)

  def render_show(conn, error) do
    render(
      conn,
      "show.html",
      title: "WebAuth",
      container: "container page page-xs",
      error: error
    )
  end

  def success(conn, _) do
    render(
      conn,
      "success.html",
      title: WebAuth,
      container: "container page page-xs"
    )
  end
end
