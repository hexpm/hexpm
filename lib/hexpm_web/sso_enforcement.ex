defmodule HexpmWeb.SSOEnforcement do
  @moduledoc """
  Turns an enforcement refusal into the response the surface it happened on
  needs.

  A browser gets sent at the provider rather than at an error page. The person
  is already a member and already knows it; the only thing missing is the
  authentication, so asking for it beats explaining it.
  """

  use HexpmWeb, :verified_routes

  import Plug.Conn, only: [halt: 1]
  import Phoenix.Controller, only: [redirect: 2]

  alias Hexpm.Accounts.SSO.Enforcement
  alias Hexpm.Accounts.Users
  alias Hexpm.Permissions

  @doc """
  Whether this request may reach the organization with the credential it
  carries.

  A browser session is on the connection, an OAuth token carries its own, and a
  key carries none.
  """
  def check(conn_or_socket, organization, principal) do
    Enforcement.check(
      organization,
      principal,
      credential(conn_or_socket),
      session_id(conn_or_socket)
    )
  end

  @doc """
  The organizations this request reaches, out of the ones the person belongs to.

  A listing resolves no single repository, so enforcement filters the set rather
  than refusing: an organization the person has not authenticated for is absent
  the same way one they do not belong to is. Refusing the whole page instead
  would take the public packages down with it.
  """
  def reachable_organizations(conn_or_socket, principal) do
    Enforcement.reachable(
      Users.all_organizations(principal),
      principal,
      credential(conn_or_socket),
      session_id(conn_or_socket)
    )
  end

  @doc """
  The organizations in a consent request the browser has not authenticated for.

  Approving would mint a token whose scope silently omits them, so the consent
  page names them instead. `repositories` is expanded first, because that is
  what the token grant does before deciding.
  """
  def unauthenticated_organizations(conn_or_socket, principal, scopes) do
    expanded = Permissions.expand_repositories_scope(principal, scopes)

    {_scopes, required} =
      Permissions.filter_sso_scopes(principal, expanded, session_id(conn_or_socket))

    required
  end

  def login_path(organization, return_path \\ nil)

  def login_path(organization, nil), do: ~p"/sso/org/#{organization}"

  def login_path(organization, return_path) do
    ~p"/sso/org/#{organization}?#{[return: return_path]}"
  end

  def redirect_to_login(%Plug.Conn{} = conn, organization) do
    conn
    |> redirect(to: login_path(organization, request_path(conn)))
    |> halt()
  end

  @doc """
  Ends a browser request that enforcement turned away.
  """
  def refuse(%Plug.Conn{} = conn, :sso_required, organization) do
    redirect_to_login(conn, organization)
  end

  def refuse(%Plug.Conn{} = conn, refusal, organization) do
    HexpmWeb.ControllerHelpers.render_error(conn, 403,
      message: Enforcement.refusal_message(refusal, organization)
    )
  end

  @doc """
  The path a LiveView is currently on, for coming back to after authenticating.
  """
  def return_path(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{path: path, query: nil} -> path
      %URI{path: path, query: query} -> path <> "?" <> query
    end
  end

  defp request_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      query -> conn.request_path <> "?" <> query
    end
  end

  defp credential(%{assigns: assigns}), do: assigns[:auth_credential]

  defp session_id(%{assigns: %{current_session: %{id: id}}}), do: id
  defp session_id(_conn_or_socket), do: nil
end
