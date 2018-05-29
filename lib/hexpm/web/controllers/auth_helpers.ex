defmodule Hexpm.Web.AuthHelpers do
  import Plug.Conn
  import Hexpm.Web.ControllerHelpers, only: [render_error: 3]

  alias Hexpm.Accounts.{Auth, Key, Organization, Organizations}
  alias Hexpm.Repository.{Package, Packages}

  def authorized(conn, opts) do
    user = conn.assigns.current_user

    if user do
      authorized(conn, user, opts[:fun], opts)
    else
      error(conn, {:error, :missing})
    end
  end

  def maybe_authorized(conn, opts) do
    authorized(conn, conn.assigns.current_user, opts[:fun], opts)
  end

  defp authorized(conn, user, funs, opts) do
    allow_unconfirmed = Keyword.get(opts, :allow_unconfirmed, false)
    domain = Keyword.get(opts, :domain)
    resource = Keyword.get(opts, :resource)
    key = conn.assigns.key
    email = conn.assigns.email

    cond do
      user && ((!email or !email.verified) && !allow_unconfirmed) ->
        error(conn, {:error, :unconfirmed})

      user && key && !verify_permissions?(key, domain, resource) ->
        error(conn, {:error, :domain})

      funs ->
        Enum.find_value(List.wrap(funs), fn fun ->
          case fun.(conn, user) do
            :ok -> nil
            other -> error(conn, other)
          end
        end) || conn

      true ->
        conn
    end
  end

  defp verify_permissions?(_key, nil, _resource) do
    true
  end

  defp verify_permissions?(key, domain, resource) do
    Key.verify_permissions?(key, domain, resource)
  end

  def error(conn, error) do
    case error do
      {:error, :missing} ->
        unauthorized(conn, "missing authentication information")

      {:error, :invalid} ->
        unauthorized(conn, "invalid authentication information")

      {:error, :password} ->
        unauthorized(conn, "invalid username and password combination")

      {:error, :key} ->
        unauthorized(conn, "invalid API key")

      {:error, :revoked_key} ->
        unauthorized(conn, "API key revoked")

      {:error, :domain} ->
        unauthorized(conn, "key not authorized for this action")

      {:error, :basic_required} ->
        unauthorized(conn, "action requires password authentication")

      {:error, :unconfirmed} ->
        forbidden(conn, "email not verified")

      {:error, :auth} ->
        forbidden(conn, "account not authorized for this action")

      {:error, :auth, reason} ->
        forbidden(conn, reason)
    end
  end

  def authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> credentials] ->
        basic_auth(credentials)

      [key] ->
        key_auth(key, conn)

      _ ->
        {:error, :missing}
    end
  end

  defp basic_auth(credentials) do
    with {:ok, decoded} <- Base.decode64(credentials),
         [username_or_email, password] = String.split(decoded, ":", parts: 2) do
      case Auth.password_auth(username_or_email, password) do
        {:ok, result} -> {:ok, result}
        :error -> {:error, :password}
      end
    else
      _ ->
        {:error, :invalid}
    end
  end

  defp key_auth(key, conn) do
    case Auth.key_auth(key, usage_info(conn)) do
      {:ok, result} -> {:ok, result}
      :error -> {:error, :key}
      :revoked -> {:error, :revoked_key}
    end
  end

  defp usage_info(%{remote_ip: remote_ip} = conn) do
    %{
      ip: remote_ip,
      used_at: NaiveDateTime.utc_now(),
      user_agent: get_req_header(conn, "user-agent")
    }
  end

  def unauthorized(conn, reason) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> render_error(401, message: reason)
  end

  def forbidden(conn, reason) do
    render_error(conn, 403, message: reason)
  end

  def package_owner(_, nil) do
    {:error, :auth}
  end

  def package_owner(%Plug.Conn{} = conn, user) do
    package_owner(conn.assigns.package, user)
  end

  def package_owner(%Package{} = package, user) do
    Packages.owner_with_access?(package, user)
    |> boolean_to_auth_error()
  end

  def maybe_full_package_owner(%Plug.Conn{} = conn, user) do
    maybe_full_package_owner(conn.assigns.organization, conn.assigns.package, user)
  end

  def maybe_full_package_owner(%Package{} = package, user) do
    maybe_full_package_owner(package.organization, package, user)
  end

  def maybe_full_package_owner(nil, nil, _user) do
    {:error, :auth}
  end

  def maybe_full_package_owner(organization, nil, user) do
    (organization.public or Organizations.access?(organization, user, "admin"))
    |> boolean_to_auth_error()
  end

  def maybe_full_package_owner(_organization, %Package{} = package, user) do
    Packages.owner_with_full_access?(package, user)
    |> boolean_to_auth_error()
  end

  def maybe_package_owner(%Plug.Conn{} = conn, user) do
    maybe_package_owner(conn.assigns.organization, conn.assigns.package, user)
  end

  def maybe_package_owner(%Package{} = package, user) do
    maybe_package_owner(package.organization, package, user)
  end

  def maybe_package_owner(nil, nil, _user) do
    {:error, :auth}
  end

  def maybe_package_owner(organization, nil, user) do
    (organization.public or Organizations.access?(organization, user, "write"))
    |> boolean_to_auth_error()
  end

  def maybe_package_owner(_organization, %Package{} = package, user) do
    Packages.owner_with_access?(package, user)
    |> boolean_to_auth_error()
  end

  def organization_access(%Plug.Conn{} = conn, user) do
    organization_access(conn.assigns.organization, user)
  end

  def organization_access(%Organization{} = organization, user) do
    (organization.public or Organizations.access?(organization, user, "read"))
    |> boolean_to_auth_error()
  end

  def organization_access(nil, _user) do
    {:error, :auth}
  end

  def maybe_organization_access(%Plug.Conn{} = conn, user) do
    maybe_organization_access(conn.assigns.organization, user)
  end

  def maybe_organization_access(%Organization{} = organization, user) do
    (organization.public or Organizations.access?(organization, user, "read"))
    |> boolean_to_auth_error()
  end

  def maybe_organization_access(nil, _user) do
    :ok
  end

  def organization_billing_active(%Plug.Conn{} = conn, user) do
    organization_billing_active(conn.assigns.organization, user)
  end

  def organization_billing_active(%Organization{} = organization, _user) do
    if organization.public or organization.billing_active do
      :ok
    else
      {:error, :auth, "organization has no active billing subscription"}
    end
  end

  def correct_user(%Plug.Conn{} = conn, user) do
    correct_user(conn.params["name"], user)
  end

  def correct_user(username_or_email, user) when is_binary(username_or_email) do
    (username_or_email in [user.username, user.email])
    |> boolean_to_auth_error()
  end

  defp boolean_to_auth_error(true), do: :ok
  defp boolean_to_auth_error(false), do: {:error, :auth}
end
