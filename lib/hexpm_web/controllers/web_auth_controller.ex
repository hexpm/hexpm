defmodule HexpmWeb.WebAuthController do
  use HexpmWeb, :controller
  @moduledoc false

  alias Hexpm.Accounts.WebAuth

  # Controller for Web Auth, a means of authenticating the cli from the website

  plug :requires_login when action == :show

  # step one of device flow
  def code(conn, %{"scope" => scope}) do
    case WebAuth.get_code(scope) do
      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid scope"})

      response ->
        json(conn, response)
    end
  end

  def show(conn, _) do
    render(conn, "show.html")
  end

  def submit(conn, %{"user_code" => user_code}) do
    audit = audit_data(conn)
    user = conn.assigns.current_user

    case WebAuth.submit(user, user_code, audit) do
      {:ok, _changeset} ->
        conn
        |> put_status(:ok)
        |> redirect(to: Routes.web_auth_path(conn, :success))

      {:error, _msg} ->
        conn
        |> put_status(400)

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
