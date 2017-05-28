defmodule Hexpm.Web.AuthHelpers do
  import Plug.Conn
  import Hexpm.Web.ControllerHelpers, only: [render_error: 3]

  alias Hexpm.Accounts.Auth

  def authorized(conn, opts) do
    fun = Keyword.get(opts, :fun, fn _, _ -> true end)
    case authorize(conn, opts) do
      {:ok, {user, key}} ->
        if fun.(conn, user) do
          conn
          |> assign(:key, key)
          |> assign(:user, user)
        else
          forbidden(conn, "account not authorized for this action")
        end
      {:error, _} = error ->
        auth_error(conn, error)
    end
  end

  def maybe_authorized(conn, opts) do
    fun = opts[:fun]
    case authorize(conn, opts) do
      {:ok, {user, key}} ->
        if !fun || fun.(conn, user) do
          conn
          |> assign(:key, key)
          |> assign(:user, user)
        else
          forbidden(conn, "account not authorized for this action")
        end
      {:error, :missing} ->
        if !fun || fun.(conn, nil) do
          conn
          |> assign(:key, nil)
          |> assign(:user, nil)
        else
          forbidden(conn, "account not authorized for this action")
        end
      {:error, _} = error ->
        auth_error(conn, error)
    end
  end

  defp auth_error(conn, error) do
    case error do
      {:error, :missing} ->
        unauthorized(conn, "missing authentication information")
      {:error, :invalid} ->
        unauthorized(conn, "invalid authentication information")
      {:error, :basic} ->
        unauthorized(conn, "invalid username and password combination")
      {:error, :key} ->
        unauthorized(conn, "invalid username and API key combination")
      {:error, :unconfirmed} ->
        forbidden(conn, "email not verified")
      {:error, :revoked_key} ->
        unauthorized(conn, "API key revoked")
    end
  end

  defp authorize(conn, opts) do
    only_basic = Keyword.get(opts, :only_basic, false)
    allow_unconfirmed = Keyword.get(opts, :allow_unconfirmed, false)

    result =
      case get_req_header(conn, "authorization") do
        ["Basic " <> credentials] when only_basic ->
          basic_auth(credentials)
        [key] when not only_basic ->
          key_auth(key)
        _ ->
          {:error, :missing}
      end

    case result do
      {:ok, {user, key, email}} ->
        if allow_unconfirmed || (email && email.verified) do
          {:ok, {user, key}}
        else
          {:error, :unconfirmed}
        end
      error ->
        error
    end
  end

  defp basic_auth(credentials) do
    case String.split(Base.decode64!(credentials), ":", parts: 2) do
      [username_or_email, password] ->
        case Auth.password_auth(username_or_email, password) do
          {:ok, user} -> {:ok, user}
          :error -> {:error, :basic}
        end
      _ ->
        {:error, :invalid}
    end
  end

  defp key_auth(key) do
    case Auth.key_auth(key) do
      {:ok, user} -> {:ok, user}
      :error      -> {:error, :key}
      :revoked    -> {:error, :revoked_key}
    end
  end

  def unauthorized(conn, reason) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> render_error(401, message: reason)
  end

  def forbidden(conn, reason) do
    conn
    |> render_error(403, message: reason)
  end

  def package_owner?(_, nil),
    do: false
  def package_owner?(%Plug.Conn{} = conn, user),
    do: package_owner?(conn.assigns.package, user)
  def package_owner?(%Hexpm.Repository.Package{} = package, user),
    do: Hexpm.Repository.Packages.owner?(package, user)

  def maybe_package_owner?(%Plug.Conn{} = conn, user),
    do: maybe_package_owner?(conn.assigns[:package], user)
  def maybe_package_owner?(nil, _user),
    do: true
  def maybe_package_owner?(%Hexpm.Repository.Package{} = package, user),
    do: Hexpm.Repository.Packages.owner?(package, user)

  def repository_access?(%Plug.Conn{} = conn, user),
    do: repository_access?(conn.assigns.repository, user)
  def repository_access?(%Hexpm.Repository.Repository{} = repository, user),
    do: Hexpm.Repository.Repositories.access?(repository, user)

  def correct_user?(%Plug.Conn{} = conn, user),
    do: correct_user?(conn.params["name"], user)
  def correct_user?(username_or_email, user) when is_binary(username_or_email),
    do: username_or_email in [user.username, user.email]
end
