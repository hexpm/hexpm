defmodule HexpmWeb.WebAuthController do
  use HexpmWeb, :controller
  @moduledoc false

  alias Hexpm.Accounts.WebAuth

  # Controller for Web Auth, a means of authenticating the cli from the website

  def code(conn, params)

  def code(conn, %{"key_name" => key_name}) do
    {:ok, response} = WebAuth.get_code(key_name)
    json(conn, response)
  end

  def code(conn, _params), do: invalid_params(conn)

  def submit(conn, params)

  def submit(conn, %{"user_code" => user_code}) do
    audit = audit_data(conn)
    user = conn.assigns.current_user

    case WebAuth.submit(user, user_code, audit) do
      {:ok, _request} ->
        conn
        |> put_status(:ok)
        |> json(%{"ok" => "ok"})

      {:error, msg} when msg == "invalid user code" ->
        invalid_parameter(conn, msg)

      {:error, msg} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{"error" => msg})
    end
  end

  def submit(conn, _params), do: invalid_params(conn)

  def access_key(conn, params)

  def access_key(conn, %{"device_code" => device_code}) do
    case WebAuth.access_key(device_code) do
      {:error, msg} when msg == "key generation failed" ->
        internal_error(conn, msg)

      {:error, msg} ->
        invalid_parameter(conn, msg)

      keys ->
        conn
        |> render(:show, keys)
    end
  end

  def access_key(conn, _params), do: invalid_params(conn)

  defp invalid_params(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{"error" => "invalid parameters"})
  end

  defp invalid_parameter(conn, msg) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"error" => msg})
  end

  defp internal_error(conn, msg) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{"error" => msg})
  end
end
