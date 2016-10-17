defmodule HexWeb.AuthHelpers do
  import Plug.Conn
  import HexWeb.ControllerHelpers, only: [render_error: 3]

  def authorized(conn, opts, auth? \\ fn _ -> true end) do
    case authorize(conn, opts) do
      {:ok, {user, key}} ->
        if auth?.(user) do
          conn
          |> assign(:key, key)
          |> assign(:user, user)
        else
          forbidden(conn, "account not authorized for this action")
        end
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
          {:error, :invalid}
      end

    case result do
      {:ok, {user, key, email}} ->
        cond do
          allow_unconfirmed || (email && email.verified) ->
            {:ok, {user, key}}
          true ->
            {:error, :unconfirmed}
        end
      error ->
        error
    end
  end

  defp basic_auth(credentials) do
    case String.split(Base.decode64!(credentials), ":", parts: 2) do
      [username_or_email, password] ->
        case HexWeb.Auth.password_auth(username_or_email, password) do
          {:ok, user} -> {:ok, user}
          :error -> {:error, :basic}
        end
      _ ->
        {:error, :invalid}
    end
  end

  defp key_auth(key) do
    case HexWeb.Auth.key_auth(key) do
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


  def package_owner?(%Plug.Conn{} = conn, user),
    do: package_owner?(conn.assigns.package, user)
  def package_owner?(%HexWeb.Package{} = package, user) do
    HexWeb.Packages.owner?(package, user)
  end

  def maybe_package_owner?(%Plug.Conn{} = conn, user),
    do: maybe_package_owner?(conn.assigns[:package], user)
  def maybe_package_owner?(nil, _user),
    do: true
  def maybe_package_owner?(%HexWeb.Package{} = package, user) do
    HexWeb.Packages.owner?(package, user)
  end

  def correct_user?(%Plug.Conn{} = conn, user),
    do: correct_user?(conn.params["name"], user)
  def correct_user?(username_or_email, user) when is_binary(username_or_email),
    do: username_or_email in [user.username, user.email]
end
