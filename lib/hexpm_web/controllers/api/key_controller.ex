defmodule HexpmWeb.API.KeyController do
  use HexpmWeb, :controller

  alias Hexpm.OAuth.Token

  plug :fetch_organization

  plug :refuse_key_credential when action == :create

  plug :authorize,
       [
         domains: ["keys"],
         allow_unconfirmed: true,
         fun: {AuthHelpers, :key_creation_access},
         authentication: :required
       ]
       when action == :create

  plug :authorize,
       [
         domains: ["keys"],
         fun: {AuthHelpers, :organization_access, [organization_role: "write"]},
         authentication: :required
       ]
       when action in [:delete, :delete_all]

  plug :authorize,
       [
         domains: [{"api", "read"}],
         authentication: :required,
         fun: {AuthHelpers, :organization_access}
       ]
       when action in [:index, :show]

  plug :require_organization_path

  def index(conn, _params) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = authing_key(conn)
    keys = Keys.all(user_or_organization)

    conn
    |> api_cache(:private)
    |> render(:index, keys: keys, authing_key: authing_key)
  end

  def show(conn, %{"name" => name}) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = authing_key(conn)
    key = Keys.get(user_or_organization, name)

    if key do
      when_stale(conn, key, fn conn ->
        conn
        |> api_cache(:private)
        |> render(:show, key: key, authing_key: authing_key)
      end)
    else
      not_found(conn)
    end
  end

  def create(conn, params) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    principal = conn.assigns.current_user || conn.assigns.current_organization
    grantor = KeyGrantor.new(user_or_organization, principal, conn.assigns.auth_credential)

    case Keys.create(user_or_organization, params, audit: audit_data(conn), grantor: grantor) do
      {:ok, %{key: key}} ->
        location = ~p"/api/keys/#{key}"

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, key: key, authing_key: nil)

      {:error, :key, changeset, _} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, %{"name" => name}) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = authing_key(conn)

    case Keys.revoke(user_or_organization, name, audit: audit_data(conn)) do
      {:ok, %{key: key}} ->
        conn
        |> api_cache(:private)
        |> put_status(200)
        |> render(:delete, key: key, authing_key: authing_key)

      _ ->
        not_found(conn)
    end
  end

  def delete_all(conn, _params) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = authing_key(conn)
    {:ok, _} = Keys.revoke_all(user_or_organization, audit: audit_data(conn))

    conn
    |> put_status(200)
    |> render(:delete, key: authing_key && Keys.get(authing_key.id), authing_key: authing_key)
  end

  defp authing_key(%{assigns: %{auth_credential: %Key{} = key}}), do: key
  defp authing_key(_conn), do: nil

  # Keys only come from a sign-in, so revoking a key leaves behind no key it
  # created. A client credentials token was exchanged for a key and counts as one.
  defp refuse_key_credential(conn, _opts) do
    case conn.assigns.auth_credential do
      %Key{} -> refuse_key_credential(conn)
      %Token{grant_type: "client_credentials"} -> refuse_key_credential(conn)
      _credential -> conn
    end
  end

  defp refuse_key_credential(%{assigns: %{organization: %Organization{} = organization}} = conn) do
    forbidden(
      conn,
      "API keys cannot create API keys, create the key on " <>
        url(~p"/dashboard/orgs/#{organization}") <>
        " or with mix hex.organization key #{organization.name} generate after mix hex.user auth"
    )
  end

  defp refuse_key_credential(conn) do
    forbidden(
      conn,
      "API keys cannot create API keys, create the key on " <> url(~p"/dashboard/keys")
    )
  end

  defp require_organization_path(conn, _opts) do
    if conn.assigns.current_organization && !conn.assigns.organization do
      not_found(conn)
    else
      conn
    end
  end
end
