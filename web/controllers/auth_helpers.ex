defmodule HexWeb.AuthHelpers do
  import Plug.Conn
  import Phoenix.Controller

  def authorized(conn, opts, auth? \\ fn _ -> true end, fun) do
    case authorize(conn, opts) do
      {:ok, user} ->
        if auth?.(user) do
          fun.(user)
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
        forbidden(conn, "account unconfirmed")
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
      {:ok, user} ->
        cond do
          allow_unconfirmed or user.confirmed ->
            {:ok, user}
          !user.confirmed ->
            {:error, :unconfirmed}
        end
      error ->
        error
    end
  end

  defp basic_auth(credentials) do
    case String.split(Base.decode64!(credentials), ":", parts: 2) do
      [username, password] ->
        user = HexWeb.Repo.get_by(HexWeb.User, username: username)
        if HexWeb.User.password_auth?(user, password) do
          {:ok, user}
        else
          {:error, :basic}
        end
      _ ->
        {:error, :invalid}
    end
  end

  defp key_auth(key) do
    case HexWeb.Auth.auth(key) do
      {:ok, user} -> {:ok, user}
      :error      -> {:error, :key}
    end
  end

  def unauthorized(conn, reason) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> put_status(401)
    |> render(HexWeb.ErrorView, :"401", message: reason)
  end

  def forbidden(conn, reason) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> put_status(403)
    |> render(HexWeb.ErrorView, :"403", message: reason)
  end

  def package_owner?(package, user) do
    HexWeb.Package.is_owner(package, user)
    |> HexWeb.Repo.one!
  end
end
