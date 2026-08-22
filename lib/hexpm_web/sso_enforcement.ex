defmodule HexpmWeb.SSOEnforcement do
  @moduledoc """
  Turns an enforcement refusal into the response the surface it happened on
  needs, and holds the parts of the provider round trip several surfaces share.

  A browser gets sent at the provider rather than at an error page. The person
  is already a member and already knows it; the only thing missing is the
  authentication, so asking for it beats explaining it.

  `:sso_required` is the only refusal a browser can get. `:auth_credential` is
  assigned by `HexpmWeb.Plugs.authenticate/2`, which runs in the `:api` and
  `:upload` pipelines only, so a browser request carries no credential and never
  takes the personal-key branch of enforcement.
  """

  use HexpmWeb, :verified_routes

  import Plug.Conn, only: [halt: 1]

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Enforcement
  alias Hexpm.Accounts.Users
  alias Hexpm.Permissions
  alias HexpmWeb.Plugs.ContentSecurityPolicy

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
  def reachable_organizations(conn_or_socket) do
    principal = conn_or_socket.assigns.current_user

    Enforcement.reachable(
      Users.all_organizations(principal),
      principal,
      credential(conn_or_socket),
      session_id(conn_or_socket)
    )
  end

  @doc """
  The repositories behind `reachable_organizations/1`, which is what the package
  queries take.
  """
  def reachable_repositories(conn_or_socket) do
    conn_or_socket
    |> reachable_organizations()
    |> Enum.map(& &1.repository)
  end

  @doc """
  The organizations in a consent request the browser has not authenticated for.

  Approving would mint a token whose scope silently omits them, so the consent
  page names them instead. `repositories` is expanded first, because that is
  what the token grant does before deciding.
  """
  def unauthenticated_organizations(conn_or_socket, principal, scopes) do
    {_scopes, required} =
      Permissions.expand_and_filter_sso_scopes(principal, scopes, session_id(conn_or_socket))

    required
  end

  def login_path(organization, return_path) do
    ~p"/sso/org/#{organization}?#{[return: return_path]}"
  end

  def redirect_to_login(%Plug.Conn{} = conn, organization) do
    conn
    |> Phoenix.Controller.redirect(to: login_path(organization, request_path(conn)))
    |> halt()
  end

  def redirect_to_login(%Phoenix.LiveView.Socket{} = socket, organization, return_path) do
    Phoenix.LiveView.redirect(socket, to: login_path(organization, return_path))
  end

  @doc """
  Ends a browser request that enforcement turned away.
  """
  def refuse(%Plug.Conn{} = conn, :sso_required, organization) do
    redirect_to_login(conn, organization)
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

  @doc """
  Where the provider sends the browser back to. One address for every flow, and
  the one registered with the provider.
  """
  def callback_url, do: url(~p"/sso/callback")

  @doc """
  Lets the browser follow a form submission through to this organization's
  provider.

  Testing a connection and authenticating a session both submit a form whose
  response redirects to the provider, and Chrome applies `form-action` to that
  redirect.
  """
  def allow_provider_form_action(conn, organization) do
    case SSO.get_connection(organization) do
      nil -> conn
      connection -> ContentSecurityPolicy.allow_form_action(conn, connection.issuer)
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
