defmodule HexpmWeb.LoginController do
  use HexpmWeb, :controller

  plug :nillify_params, ["return"]

  def show(conn, params) do
    if logged_in?(conn) do
      redirect_return(conn, conn.assigns.current_user, conn.params["return"])
    else
      conn
      |> assign(:token, params["token"])
      |> render_show()
    end
  end

  def create(conn, %{"username" => username, "password" => password} = params) do
    case password_auth(username, password) do
      {:ok, user} ->
        breached? = Hexpm.Pwned.password_breached?(password)
        account_linked? = maybe_link_account(user, params["token"])

        login(conn, user, password_breached: breached?, account_linked?: account_linked?)

      {:error, reason} ->
        conn
        |> put_flash(:error, auth_error_message(reason))
        |> put_status(400)
        |> render_show()
    end
  end

  defp maybe_link_account(_user, nil), do: false

  defp maybe_link_account(user, token) do
    {:ok, _account_link} = Hexpm.Accounts.Users.link_github_from_token(user, token)
    true
  end

  def delete(conn, _params) do
    conn
    |> delete_session("user_id")
    |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end

  def start_session(conn, user, return) do
    conn
    |> configure_session(renew: true)
    |> put_session("user_id", user.id)
    |> redirect_return(user, return)
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
    path = return || Routes.user_path(conn, :show, user)
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
      hexdocs: conn.params["hexdocs"],
      token: conn.assigns[:token]
    )
  end

  defp login(conn, %User{id: user_id, tfa: %{tfa_enabled: true, app_enabled: true}},
         password_breached: breached?,
         account_linked?: linked?
       ) do
    conn
    |> configure_session(renew: true)
    |> put_session("tfa_user_id", %{uid: user_id, return: conn.params["return"]})
    |> maybe_put_breached_flash(breached?)
    |> maybe_put_linked_flash(linked?)
    |> redirect(to: Routes.tfa_auth_path(conn, :show))
  end

  defp login(conn, user, password_breached: breached?, account_linked?: linked?) do
    conn
    |> maybe_put_breached_flash(breached?)
    |> maybe_put_linked_flash(linked?)
    |> start_session(user, conn.params["return"])
  end

  defp maybe_put_breached_flash(conn, false), do: conn

  defp maybe_put_breached_flash(conn, true) do
    put_flash(conn, :error, password_breached_message(conn, []))
  end

  defp maybe_put_linked_flash(conn, true), do: put_flash(conn, :info, account_linked_message())
  defp maybe_put_linked_flash(conn, _), do: conn
end
