defmodule HexpmWeb.API.AuthController do
  use HexpmWeb, :controller

  plug :required_params, ["domain"]
  plug :authorize, authentication: :required

  def show(conn, %{"domain" => domain} = params) do
    auth_credential = conn.assigns.auth_credential
    user_or_organization = conn.assigns.current_user || conn.assigns.current_organization
    resource = params["resource"]

    # Two-level permission check:
    # 1. API-level: Check if the API key/OAuth token has the required scopes/permissions
    has_api_permission =
      if auth_credential do
        Hexpm.Permissions.verify_access?(auth_credential, domain, resource)
      else
        false
      end

    if has_api_permission do
      # 2. User-level: Check if the authenticated user/organization actually owns/has access to the resource
      case Hexpm.Permissions.verify_user_access(user_or_organization, domain, resource) do
        {:ok, nil} ->
          success(conn)

        {:ok, verified} ->
          organization = resource_organization(verified)

          with :ok <- organization_billing_active(organization, user_or_organization),
               :ok <-
                 sso_enforced_credential(
                   conn,
                   domain,
                   verified,
                   organization,
                   user_or_organization
                 ) do
            success(conn)
          else
            error -> error(conn, error)
          end

        :error ->
          error(conn, {:error, :auth})
      end
    else
      error(conn, {:error, :domain})
    end
  end

  # The repository and docs domains verify against an organization, the package
  # domain against a package. Billing is about who pays for the repository the
  # package lives in, which is the public organization for a public package and
  # is always active.
  defp resource_organization(%Package{} = package) do
    Hexpm.Repo.preload(package, repository: :organization).repository.organization
  end

  defp resource_organization(%Organization{} = organization), do: organization

  # An OAuth token's repository and docs scopes are minted against a live
  # organization access session when the token is refreshed, so the scope check
  # above already carries the decision. Re-deciding it here would make this
  # endpoint disagree with the edge, which verifies the same scopes without ever
  # reaching the database.
  #
  # The package domain carries no such decision: a bare `api` or `api:write`
  # scope satisfies it, and nothing filters those against an organization access
  # session, so this endpoint takes the decision itself. It also resolves the
  # organization differently from billing, because a public package's owner is
  # what enforcement is about rather than the repository it sits in.
  defp sso_enforced_credential(conn, "package", %Package{} = package, _organization, principal) do
    package_sso_enforced(conn, package, principal)
  end

  defp sso_enforced_credential(conn, _domain, _verified, organization, user_or_organization) do
    case conn.assigns.auth_credential do
      %Hexpm.OAuth.Token{} -> :ok
      _credential -> sso_enforced(conn, organization, user_or_organization)
    end
  end

  defp success(conn) do
    case conn.assigns.auth_credential do
      %Key{} = key ->
        conn
        |> put_resp_header("x-hex-key-id", Integer.to_string(key.id))
        |> render(:show, key: key)

      _ ->
        send_resp(conn, 204, "")
    end
  end
end
