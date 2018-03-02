defmodule Hexpm.Web.AuthHelpers do
  import Plug.Conn
  import Hexpm.Web.ControllerHelpers, only: [render_error: 3]

  alias Hexpm.Accounts.{Auth, Key}
  alias Hexpm.Repository.{Package, Packages, Repositories, Repository}

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

  defp authorized(conn, user, fun, opts) do
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

      fun ->
        case fun.(conn, user) do
          :ok -> conn
          other -> error(conn, other)
        end

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
        key_auth(key)

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

  defp key_auth(key) do
    case Auth.key_auth(key) do
      {:ok, result} -> {:ok, result}
      :error -> {:error, :key}
      :revoked -> {:error, :revoked_key}
    end
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

  def maybe_package_owner(%Plug.Conn{} = conn, user) do
    maybe_package_owner(conn.assigns.repository, conn.assigns.package, user)
  end

  def maybe_package_owner(%Package{} = package, user) do
    maybe_package_owner(package.repository, package, user)
  end

  def maybe_package_owner(nil, nil, _user) do
    {:error, :auth}
  end

  def maybe_package_owner(repository, nil, user) do
    (repository.public or Repositories.access?(repository, user, "write"))
    |> boolean_to_auth_error()
  end

  def maybe_package_owner(_repository, %Package{} = package, user) do
    Packages.owner_with_access?(package, user)
    |> boolean_to_auth_error()
  end

  def repository_access(%Plug.Conn{} = conn, user) do
    repository_access(conn.assigns.repository, user)
  end

  def repository_access(%Repository{} = repository, user) do
    (repository.public or Repositories.access?(repository, user, "read"))
    |> boolean_to_auth_error()
  end

  def repository_access(nil, _user) do
    {:error, :auth}
  end

  def maybe_repository_access(%Plug.Conn{} = conn, user) do
    maybe_repository_access(conn.assigns.repository, user)
  end

  def maybe_repository_access(%Hexpm.Repository.Repository{} = repository, user) do
    (repository.public or Hexpm.Repository.Repositories.access?(repository, user, "read"))
    |> boolean_to_auth_error()
  end

  def maybe_repository_access(nil, _user) do
    :ok
  end

  def repository_billing_active(%Plug.Conn{} = conn, user) do
    repository_billing_active(conn.assigns.repository, user)
  end

  def repository_billing_active(%Repository{} = repository, _user) do
    if repository.public or repository.billing_active do
      :ok
    else
      {:error, :auth, "repository has no active billing subscription"}
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
