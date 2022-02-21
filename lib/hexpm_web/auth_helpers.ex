defmodule HexpmWeb.AuthHelpers do
  import Plug.Conn
  import HexpmWeb.ControllerHelpers, only: [render_error: 3]

  alias Hexpm.Accounts.{Auth, Key, Organization, Organizations, User}
  alias Hexpm.Repository.{Package, Packages, PackageOwner, Repository}

  def authorize(conn, opts) do
    user_or_organization = conn.assigns.current_user || conn.assigns.current_organization

    if user_or_organization || opts[:authentication] != :required do
      authorized(conn, user_or_organization, opts[:fun], opts)
    else
      error(conn, {:error, :missing})
    end
  end

  defp authorized(conn, %User{service: true}, _funs, _opts) do
    conn
  end

  defp authorized(conn, user_or_organization, funs, opts) do
    domain = Keyword.get(opts, :domain)
    resource = Keyword.get(opts, :resource)
    key = conn.assigns.key
    email = conn.assigns.email

    cond do
      not verified_user?(user_or_organization, email, opts) ->
        error(conn, {:error, :unconfirmed})

      user_or_organization && !verify_permissions?(key, domain, resource) ->
        error(conn, {:error, :domain})

      funs ->
        Enum.find_value(List.wrap(funs), fn fun ->
          case apply_authorization_fun(fun, conn, user_or_organization, opts[:opts]) do
            :ok -> nil
            other -> error(conn, other)
          end
        end) || conn

      true ->
        conn
    end
  end

  defp apply_authorization_fun(fun, conn, user_or_organization, _opts = nil) do
    fun.(conn, user_or_organization)
  end

  defp apply_authorization_fun(fun, conn, user_or_organization, opts) do
    fun.(conn, user_or_organization, opts)
  end

  defp verified_user?(%User{}, email, opts) do
    allow_unconfirmed = Keyword.get(opts, :allow_unconfirmed, false)
    allow_unconfirmed || (email && email.verified)
  end

  defp verified_user?(%Organization{}, _email, _opts) do
    true
  end

  defp verified_user?(nil, _email, _opts) do
    true
  end

  defp verify_permissions?(nil, _domain, _resource) do
    true
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

      {:error, :unconfirmed} ->
        forbidden(conn, "email not verified")

      {:error, :auth} ->
        forbidden(conn, "account not authorized for this action")

      {:error, :auth, reason} ->
        forbidden(conn, reason)

      {:error, :not_found} ->
        HexpmWeb.ControllerHelpers.not_found(conn)
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
      used_at: DateTime.utc_now(),
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

  def package_owner(conn, user_or_organization, opts \\ [])

  def package_owner(%Plug.Conn{} = conn, user_or_organization, opts) do
    package_owner(conn.assigns.repository, conn.assigns.package, user_or_organization, opts)
  end

  def package_owner(
        %Repository{} = repository,
        %Package{} = package,
        %Organization{} = organization,
        opts
      ) do
    owner_level = opts[:owner_level] || "maintainer"

    cond do
      repository.organization_id == organization.id -> :ok
      Packages.owner_with_access?(package, organization.user, owner_level) -> :ok
      repository.id == 1 -> {:error, :auth}
      true -> {:error, :not_found}
    end
  end

  def package_owner(%Repository{} = repository, %Package{} = package, %User{} = user, opts) do
    cond do
      Packages.owner_with_access?(package, user, opts[:owner_level] || "maintainer") -> :ok
      repository.id == 1 -> {:error, :auth}
      true -> {:error, :not_found}
    end
  end

  def package_owner(%Repository{} = repository, %Package{}, nil, _opts) do
    if repository.id == 1 do
      {:error, :auth}
    else
      {:error, :not_found}
    end
  end

  def package_owner(
        %Repository{} = repository,
        nil = _package,
        %Organization{} = organization,
        _opts
      ) do
    cond do
      repository.id == 1 -> :ok
      repository.organization_id == organization.id -> :ok
      true -> {:error, :not_found}
    end
  end

  def package_owner(%Repository{} = repository, nil = _package, %User{} = user, opts) do
    expected_role = PackageOwner.level_to_organization_role(opts[:owner_level] || "maintainer")
    actual_role = Organizations.get_role(repository.organization, user)

    cond do
      repository.id == 1 -> :ok
      actual_role && actual_role in Organization.role_or_higher(expected_role) -> :ok
      actual_role -> {:error, :auth}
      true -> {:error, :not_found}
    end
  end

  def package_owner(%Repository{} = repository, nil = _package, nil = _user, _opts) do
    boolean_to_not_found(repository.id == 1)
  end

  def package_owner(nil = _repository, _package, _user, _opts) do
    {:error, :not_found}
  end

  def organization_access(conn, user_or_organization, opts \\ [])

  def organization_access(%Plug.Conn{} = conn, user_or_organization, opts) do
    organization_access(conn.assigns.organization, user_or_organization, opts)
  end

  def organization_access(%Organization{id: 1}, _user_or_organization, opts) do
    role = opts[:organization_role] || "read"
    boolean_to_auth_error(role == "read")
  end

  def organization_access(nil = _organization, _user_or_organization, _opts) do
    :ok
  end

  def organization_access(%Organization{} = organization, user_or_organization, opts) do
    cond do
      Organizations.access?(
        organization,
        user_or_organization,
        opts[:organization_role] || "read"
      ) ->
        :ok

      organization.id == 1 ->
        {:error, :auth}

      true ->
        {:error, :not_found}
    end
  end

  def organization_billing_active(conn, user_or_organization, opts \\ [])

  def organization_billing_active(%Plug.Conn{} = conn, _user_or_organization, _opts) do
    organization_billing_active(conn.assigns.organization, nil)
  end

  def organization_billing_active(%Organization{} = organization, _user_or_organization, _opts) do
    if organization.id == 1 or Organization.billing_active?(organization) do
      :ok
    else
      {:error, :auth, "organization has no active billing subscription"}
    end
  end

  def organization_billing_active(nil = _organization, _user_or_organization, _opts) do
    :ok
  end

  defp boolean_to_auth_error(true), do: :ok
  defp boolean_to_auth_error(false), do: {:error, :auth}

  defp boolean_to_not_found(true), do: :ok
  defp boolean_to_not_found(false), do: {:error, :not_found}
end
