defmodule HexpmWeb.LoginController do
  use HexpmWeb, :controller
  require Logger
  alias HexpmWeb.Plugs.Attack

  plug :nillify_params, ["return"]

  def show(conn, _params) do
    if logged_in?(conn) do
      redirect_return(conn, conn.assigns.current_user, conn.params["return"])
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
    alias Hexpm.UserSessions

    # Revoke browser session if exists
    if session_token = get_session(conn, "session_token") do
      case Base.decode64(session_token) do
        {:ok, decoded_token} ->
          case UserSessions.get_browser_session_by_token(decoded_token) do
            nil -> :ok
            session -> UserSessions.revoke(session)
          end

        _ ->
          :ok
      end
    end

    conn
    |> delete_session("session_token")
    |> redirect(to: ~p"/")
  end

  def start_session(conn, user, return) do
    conn
    |> start_session_internal(user)
    |> redirect_return(user, return)
  end

  def start_session_internal(conn, user) do
    alias Hexpm.UserSessions

    # Create browser session
    {:ok, _user_session, session_token} =
      UserSessions.create_browser_session(user, name: detect_browser(conn))

    conn
    |> configure_session(renew: true)
    |> put_session("session_token", Base.encode64(session_token))
  end

  defp detect_browser(conn) do
    user_agent = get_req_header(conn, "user-agent") |> List.first()

    cond do
      is_nil(user_agent) -> "Unknown Browser"
      String.contains?(user_agent, "Chrome") -> "Chrome"
      String.contains?(user_agent, "Firefox") -> "Firefox"
      String.contains?(user_agent, "Safari") -> "Safari"
      String.contains?(user_agent, "Edge") -> "Edge"
      true -> "Browser Session"
    end
  end

  defp redirect_return(%{params: %{"hexdocs" => organization}} = conn, user, return) do
    case generate_hexdocs_key(user, organization) do
      {:ok, key} ->
        docs_url =
          Application.get_env(:hexpm, :docs_url)
          |> String.replace("://", "://#{organization}.")

        url = "#{docs_url}#{return}?key=#{key.user_secret}"
        redirect(conn, external: url)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "You don't have access to organization #{organization}")
        |> put_status(400)
        |> render_show()
    end
  end

  defp redirect_return(conn, user, return) do
    path = return || ~p"/users/#{user}"
    redirect(conn, to: path)
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
      return: conn.params["return"],
      hexdocs: conn.params["hexdocs"]
    )
  end

  defp login(conn, %User{id: user_id, tfa: %{tfa_enabled: true, app_enabled: true}} = user,
         password_breached: breached?
       ) do
    alias Hexpm.UserSessions

    # Pre-create browser session for after TFA
    {:ok, _user_session, session_token} =
      UserSessions.create_browser_session(user, name: detect_browser(conn))

    conn
    |> configure_session(renew: true)
    |> put_session("tfa_user_id", %{
      "uid" => user_id,
      "return" => conn.params["return"],
      "session_token" => Base.encode64(session_token)
    })
    |> maybe_put_flash(breached?)
    |> redirect(to: ~p"/tfa")
  end

  defp login(conn, user, password_breached: breached?) do
    conn
    |> maybe_put_flash(breached?)
    |> start_session(user, conn.params["return"])
  end

  defp maybe_put_flash(conn, false), do: conn

  defp maybe_put_flash(conn, true) do
    put_flash(conn, :raw_error, password_breached_message())
  end
end
