defmodule HexpmWeb.AuthHelpers do
  import Plug.Conn
  import HexpmWeb.ControllerHelpers, only: [render_error: 3]

  alias Hexpm.Accounts.{Auth, Key, Organization, Organizations, User}
  alias Hexpm.Repository.{Package, Packages, Repository}

  def authorized(conn, opts) do
    user_or_organization = conn.assigns.current_user || conn.assigns.current_organization

    if user_or_organization do
      authorized(conn, user_or_organization, opts[:fun], opts)
    else
      error(conn, {:error, :missing})
    end
  end

  def maybe_authorized(conn, opts) do
    user_or_organization = conn.assigns.current_user || conn.assigns.current_organization
    authorized(conn, user_or_organization, opts[:fun], opts)
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
          case fun.(conn, user_or_organization) do
            :ok -> nil
            other -> error(conn, other)
          end
        end) || conn

      true ->
        conn
    end
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

  def package_owner(_, nil) do
    {:error, :auth}
  end

  def package_owner(%Plug.Conn{} = conn, user_or_organization) do
    package_owner(conn.assigns.package, user_or_organization)
  end

  def package_owner(%Package{} = package, %User{} = user) do
    Packages.owner_with_access?(package, user)
    |> boolean_to_auth_error()
  end

  def package_owner(%Package{} = package, %Organization{} = organization) do
    boolean_to_auth_error(package.repository.organization_id == organization.id)
  end

  def maybe_full_package_owner(%Plug.Conn{} = conn, user_or_organization) do
    maybe_full_package_owner(
      conn.assigns.repository,
      conn.assigns.package,
      user_or_organization
    )
  end

  def maybe_full_package_owner(%Package{} = package, user_or_organization) do
    maybe_full_package_owner(package.repository, package, user_or_organization)
  end

  def maybe_full_package_owner(nil = _repository, nil = _package, _user_or_organization) do
    {:error, :auth}
  end

  def maybe_full_package_owner(_repository, _package, %Organization{}) do
    {:error, :auth}
  end

  def maybe_full_package_owner(repository, nil = _package, %User{} = user) do
    (repository.public or Organizations.access?(repository.organization, user, "admin"))
    |> boolean_to_auth_error()
  end

  def maybe_full_package_owner(_repository, %Package{} = package, %User{} = user) do
    Packages.owner_with_full_access?(package, user)
    |> boolean_to_auth_error()
  end

  def maybe_package_owner(%Plug.Conn{} = conn, user_or_organization) do
    maybe_package_owner(conn.assigns.repository, conn.assigns.package, user_or_organization)
  end

  def maybe_package_owner(%Package{} = package, user_or_organization) do
    maybe_package_owner(package.repository, package, user_or_organization)
  end

  def maybe_package_owner(nil = _repository, nil = _package, _user) do
    {:error, :auth}
  end

  def maybe_package_owner(repository, _package, %Organization{id: id}) do
    boolean_to_auth_error(repository.organization_id == id)
  end

  def maybe_package_owner(repository, nil = _package, %User{} = user) do
    (repository.public or Organizations.access?(repository.organization, user, "write"))
    |> boolean_to_auth_error()
  end

  def maybe_package_owner(_repository, %Package{} = package, %User{} = user) do
    Packages.owner_with_access?(package, user)
    |> boolean_to_auth_error()
  end

  def organization_access_write(conn, user_or_organization) do
    organization_access(conn, user_or_organization, "write")
  end

  def organization_access_admin(conn, user_or_organization) do
    organization_access(conn, user_or_organization, "admin")
  end

  def organization_access(conn, user_or_organization, role \\ "read")

  def organization_access(%Plug.Conn{} = conn, user_or_organization, role) do
    organization_access(conn.assigns.organization, user_or_organization, role)
  end

  def organization_access(%Organization{} = organization, %User{} = user, role) do
    Organizations.access?(organization, user, role)
    |> boolean_to_auth_error()
  end

  def organization_access(%Organization{} = organization, %Organization{id: id}, _role) do
    boolean_to_auth_error(organization.id == id)
  end

  def organization_access(%Organization{}, nil = _user_or_organization, _role) do
    {:error, :auth}
  end

  def organization_access(nil = _organization, _user_or_organization, _role) do
    {:error, :auth}
  end

  def maybe_organization_access_write(conn, user_or_organization) do
    maybe_organization_access(conn, user_or_organization, "write")
  end

  def maybe_organization_access(conn, user_or_organization, role \\ "read")

  def maybe_organization_access(%Plug.Conn{} = conn, user_or_organization, role) do
    maybe_organization_access(conn.assigns.organization, user_or_organization, role)
  end

  def maybe_organization_access(%Organization{} = organization, %User{} = user, role) do
    Organizations.access?(organization, user, role)
    |> boolean_to_auth_error()
  end

  def maybe_organization_access(%Organization{} = organization, %Organization{id: id}, _role) do
    boolean_to_auth_error(organization.id == id)
  end

  def maybe_organization_access(nil = _organization, _user_or_organization, _role) do
    :ok
  end

  def organization_billing_active(%Plug.Conn{} = conn, _user_or_organization) do
    organization_billing_active(conn.assigns.organization, nil)
  end

  def organization_billing_active(%Organization{billing_active: true}, _user_or_organization),
    do: :ok

  def organization_billing_active(%Organization{billing_active: false}, _user_or_organization),
    do: {:error, :auth, "organization has no active billing subscription"}

  def repository_access(%Plug.Conn{} = conn, user_or_organization) do
    repository_access(conn.assigns.repository, user_or_organization)
  end

  def repository_access(%Repository{public: false} = repository, %User{} = user) do
    Organizations.access?(repository.organization, user, "read")
    |> boolean_to_auth_error()
  end

  def repository_access(%Repository{public: false} = repository, %Organization{id: id}) do
    boolean_to_auth_error(repository.organization_id == id)
  end

  def repository_access(%Repository{} = repository, _user_or_organization) do
    boolean_to_auth_error(repository.public)
  end

  def repository_access(nil = _repository, _user_or_organization) do
    {:error, :auth}
  end

  def maybe_repository_access(%Plug.Conn{} = conn, user_or_organization) do
    maybe_repository_access(conn.assigns.repository, user_or_organization)
  end

  def maybe_repository_access(%Repository{public: false} = repository, %User{} = user) do
    Organizations.access?(repository.organization, user, "read")
    |> boolean_to_auth_error()
  end

  def maybe_repository_access(%Repository{public: false} = repository, %Organization{id: id}) do
    boolean_to_auth_error(repository.organization_id == id)
  end

  def maybe_repository_access(%Repository{} = repository, nil = _user_or_organization) do
    boolean_to_auth_error(repository.public)
  end

  def maybe_repository_access(nil = _repository, _user_or_organization) do
    :ok
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
