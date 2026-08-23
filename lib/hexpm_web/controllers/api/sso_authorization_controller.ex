defmodule HexpmWeb.API.SSOAuthorizationController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.{SSO, User}
  alias Hexpm.OAuth.Token

  plug :authorize, authentication: :required

  def create(conn, params) do
    with {:ok, user_session_id} <- session(conn),
         {:ok, authorization} <-
           SSO.request_authorization(
             conn.assigns.current_user,
             user_session_id,
             params["organizations"]
           ) do
      conn
      |> put_status(201)
      |> render(:show, authorization: authorization)
    else
      {:error, reason} -> render_error(conn, 422, message: message(reason))
    end
  end

  # The session in hand is the one being authorized, so it has to be one that
  # can hold organization access. A static key has nowhere to put it, and a
  # token exchanged from one holds the key's standing: enforcement reads it as a
  # key, so an organization access session written against it would never be
  # looked at and the caller would be refused again after the round trip.
  defp session(conn) do
    case {conn.assigns.current_user, conn.assigns.auth_credential} do
      {%User{}, %Token{grant_type: "client_credentials"}} ->
        {:error, :invalid_session}

      {%User{}, %Token{user_session_id: user_session_id}} when is_integer(user_session_id) ->
        {:ok, user_session_id}

      _other ->
        {:error, :invalid_session}
    end
  end

  defp message(:invalid_session) do
    "SSO re-authorization is for an OAuth session, run mix hex.user auth to get one"
  end

  defp message(:invalid_organizations) do
    "organizations must be a list of organization names"
  end

  # One answer for a name that does not exist, one the caller is not a member
  # of, and one that does not require SSO, so asking tells them nothing they
  # did not already know.
  defp message(:not_governed) do
    "SSO authentication is not required for the requested organizations"
  end
end
