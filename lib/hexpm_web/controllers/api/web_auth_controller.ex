defmodule HexpmWeb.API.WebAuthController do
  use HexpmWeb, :controller
  @moduledoc false

  alias Hexpm.Accounts.WebAuth

  # Controller for Web Auth, a means of authenticating the cli from the website

  def code(conn, %{"key_name" => key_name}) do
    {:ok, response} = WebAuth.get_code(key_name)
    render(conn, :code, response)
  end

  def code(conn, _params), do: invalid_params(conn)

  def access_key(conn, %{"device_code" => device_code}) do
    {user_agent, _} = audit_data(conn)

    case WebAuth.access_key(device_code, user_agent) do
      {:error, msg} when msg == "key generation failed" ->
        internal_error(conn, msg)

      {:error, msg} ->
        invalid_parameter(conn, msg)

      {:ok, keys} ->
        render(conn, :access, keys)
    end
  end

  def access_key(conn, _params), do: invalid_params(conn)

  defp invalid_params(conn) do
    render_error(conn, :bad_request, message: "invalid parameters")
  end

  defp invalid_parameter(conn, msg) do
    render_error(conn, :unprocessable_entity, message: msg)
  end

  defp internal_error(conn, msg) do
    render_error(conn, :internal_server_error, message: msg)
  end
end
