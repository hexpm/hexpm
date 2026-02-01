defmodule HexpmWeb.LoginController do
  use HexpmWeb, :controller
  require Logger
  alias Hexpm.UserSessions
  alias HexpmWeb.Plugs.Attack

  plug :nillify_params, ["return"]

  def show(conn, _params) do
    if logged_in?(conn) do
      redirect_return(conn, conn.assigns.current_user, safe_string(conn.params["return"]))
    else
      render_show(conn)
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        breached? = Hexpm.Pwned.password_breached?(password)
        login(conn, user, password_breached: breached?)

      {:error, reason} ->
        Logger.warning("Failed login attempt",
          username: username,
          ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
          user_agent: get_req_header(conn, "user-agent") |> List.first()
        )

        case Attack.login_ip_throttle(conn.remote_ip) do
          {:block, _data} ->
            conn
            |> put_flash(:error, "Too many login attempts from your IP. Please try again later.")
            |> put_status(429)
            |> render_show()

          {:allow, _data} ->
            conn
            |> put_flash(:error, auth_error_message(reason))
            |> put_status(400)
            |> render_show()
        end
    end
  end

  def delete(conn, _params) do
    # Revoke browser session if exists
    if session_token = get_session(conn, "session_token") do
      case Base.decode64(session_token) do
        {:ok, decoded_token} ->
          case UserSessions.get_browser_session_by_token(decoded_token) do
            nil -> :ok
            session -> UserSessions.revoke(session, nil, audit: audit_data(conn))
          end

        _ ->
          :ok
      end
    end

    conn
    |> delete_session("session_token")
    |> redirect(to: ~p"/")
  end

  defp start_session(conn, user, return) do
    conn
    |> start_session_internal(user)
    |> redirect_return(user, return)
  end

  defp redirect_return(%{params: %{"hexdocs" => organization}} = conn, user, return)
       when is_binary(organization) do
    case generate_hexdocs_key(user, organization) do
      {:ok, key} ->
        docs_url =
          Application.get_env(:hexpm, :docs_url)
          |> String.replace("://", "://#{organization}.")

        url = "#{docs_url}#{safe_path(return)}?key=#{key.user_secret}"
        redirect(conn, external: url)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "You don't have access to organization #{organization}")
        |> put_status(400)
        |> render_show()
    end
  end

  defp redirect_return(conn, _user, "/" <> _ = return) do
    redirect(conn, to: return)
  end

  defp redirect_return(conn, user, _return) do
    redirect(conn, to: ~p"/users/#{user}")
  end

  defp generate_hexdocs_key(user, organization) do
    Keys.create_for_docs(user, organization)
  end

  defp render_show(conn) do
    render(
      conn,
      "show.html",
      title: "Log in",
      container: "container page page-xs login",
      return: safe_string(conn.params["return"]),
      hexdocs: safe_string(conn.params["hexdocs"])
    )
  end

  defp login(conn, %User{tfa: %{secret: secret}} = user, password_breached: breached?)
       when is_binary(secret) do
    conn
    |> start_tfa_session(user, safe_string(conn.params["return"]))
    |> maybe_put_flash(breached?)
    |> redirect(to: ~p"/tfa")
  end

  defp login(conn, user, password_breached: breached?) do
    conn
    |> maybe_put_flash(breached?)
    |> start_session(user, safe_string(conn.params["return"]))
  end

  defp safe_path("/" <> _ = path), do: path
  defp safe_path(_), do: "/"

  defp maybe_put_flash(conn, false), do: conn

  defp maybe_put_flash(conn, true) do
    put_flash(conn, :raw_error, password_breached_message())
  end
end
