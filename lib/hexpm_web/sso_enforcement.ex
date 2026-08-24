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
  alias Hexpm.Accounts.{User, Users}
  alias Hexpm.Permissions
  alias Hexpm.Repository.{Package, Packages}
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
  Whether this request may act on a package, and which organization turned it
  away.

  A package's own repository is the wrong thing to enforce against when the
  package lives in the public repository: that repository belongs to the public
  organization, which enforcement never governs. An organization can own a
  package that lives there, and its membership is what lets its members act on
  the package, so the owners are what enforcement runs against. A public package
  no organization owns has nothing to enforce.

  Every caller that decides something about a package goes through here, because
  the resolution is the part that was wrong rather than the check.
  """
  def check_package(conn_or_socket, package, principal, level \\ "maintainer")

  def check_package(conn_or_socket, %Package{repository_id: 1} = package, %User{} = user, level) do
    package
    |> Packages.owner_organizations(user, level)
    |> Enum.reduce_while(:ok, fn organization, :ok ->
      case check(conn_or_socket, organization, user) do
        :ok -> {:cont, :ok}
        {:error, refusal} -> {:halt, {:error, refusal, organization}}
      end
    end)
  end

  def check_package(conn_or_socket, %Package{} = package, principal, _level) do
    package
    |> Hexpm.Repo.preload(repository: :organization)
    |> Map.fetch!(:repository)
    |> Map.fetch!(:organization)
    |> check_organization(conn_or_socket, principal)
  end

  # Publishing a package that does not exist yet has no owners to resolve, so
  # the repository it is going into is all there is to enforce against.
  def check_package(conn_or_socket, _package, principal, _level) do
    check_organization(conn_or_socket.assigns[:organization], conn_or_socket, principal)
  end

  defp check_organization(organization, conn_or_socket, principal) do
    case check(conn_or_socket, organization, principal) do
      :ok -> :ok
      {:error, refusal} -> {:error, refusal, organization}
    end
  end

  @doc """
  The organizations this request reaches, out of the ones the person belongs to.

  A listing resolves no single repository, so enforcement filters the set rather
  than refusing: an organization the person has not authenticated for is absent
  the same way one they do not belong to is. Refusing the whole page instead
  would take the public packages down with it.

  `reload: true` reads the memberships from the database rather than from the
  association the caller loaded, which is what a connected LiveView needs: it
  loaded them at mount and a member removed since is governed by nothing.
  """
  def reachable_organizations(conn_or_socket, opts \\ []) do
    user = conn_or_socket.assigns.current_user

    organizations =
      if Keyword.get(opts, :reload, false) do
        Users.reload_organizations(user)
      else
        Users.all_organizations(user)
      end

    reachable(conn_or_socket, organizations)
  end

  @doc """
  The same filter over a set of organizations the caller has already resolved.
  """
  def reachable(conn_or_socket, organizations) do
    Enforcement.reachable(
      organizations,
      conn_or_socket.assigns.current_user,
      credential(conn_or_socket),
      session_id(conn_or_socket)
    )
  end

  @doc """
  The repositories behind `reachable_organizations/1`, which is what the package
  queries take.
  """
  def reachable_repositories(conn_or_socket, opts \\ []) do
    conn_or_socket
    |> reachable_organizations(opts)
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

  @doc """
  The organization access this browser session is carrying, which approving a
  client would copy onto the client's own session.
  """
  def granted_organizations(conn_or_socket, user) do
    case session_id(conn_or_socket) do
      nil -> []
      id -> SSO.granted_organization_ids(id, user.id)
    end
  end

  def login_path(organization, nil), do: ~p"/sso/org/#{organization}"

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
      connection -> ContentSecurityPolicy.allow_form_action(conn, provider_url(connection))
    end
  end

  # The redirect goes to the authorization endpoint discovery returned, which
  # nothing requires to share an origin with the issuer.
  defp provider_url(%{discovery_document: %{"authorization_endpoint" => endpoint}})
       when is_binary(endpoint),
       do: endpoint

  defp provider_url(connection), do: connection.issuer

  # A GET is worth resuming, and coming back to it is the whole point. Anything
  # else is not: the provider sends the browser back with a GET, so the method
  # and the body are gone by then. Replaying the path would either 404, on the
  # routes with no GET counterpart, or load the page and say the action
  # succeeded when nothing ran. The page the form was on is where the person
  # can try again.
  defp request_path(%{method: "GET"} = conn) do
    case conn.query_string do
      "" -> conn.request_path
      query -> conn.request_path <> "?" <> query
    end
  end

  defp request_path(conn) do
    conn
    |> Plug.Conn.get_req_header("referer")
    |> List.first()
    |> referer_path()
  end

  defp referer_path(referer) when is_binary(referer) do
    case URI.parse(referer) do
      %URI{path: path, query: nil} when is_binary(path) -> SSO.allowed_return_path(path)
      %URI{path: path, query: query} when is_binary(path) -> allowed_return_path(path, query)
      _other -> nil
    end
  end

  defp referer_path(_referer), do: nil

  defp allowed_return_path(path, query) do
    if SSO.allowed_return_path(path), do: path <> "?" <> query
  end

  defp credential(%{assigns: assigns}), do: assigns[:auth_credential]

  defp session_id(%{assigns: %{current_session: %{id: id}}}), do: id
  defp session_id(_conn_or_socket), do: nil
end
