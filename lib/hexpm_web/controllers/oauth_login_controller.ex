defmodule HexpmWeb.OAuthLoginController do
  use HexpmWeb, :controller

  require Logger

  plug :nillify_params, ["return"]

  def create(conn, %{"code" => code}) do
    with {:ok, access_token} <- Hexpm.OAuthProviders.GitHub.get_access_token(code),
         {:ok, %{id: user_id, email: email}} <-
           Hexpm.OAuthProviders.GitHub.get_user(access_token) do
      user = Hexpm.Accounts.Users.get_by_github_id(user_id)
      forward_to_login_or_sign_up(conn, user, user_id, email)
    else
      error ->
        Logger.error("Error trying to create OAuthLogin: #{inspect(error)}")

        conn
        |> put_flash(:error, "Something went wrong, try again later")
        |> redirect(to: Routes.login_path(conn, :show))
    end
  end

  defp forward_to_login_or_sign_up(conn, nil, github_user_id, github_email) do
    if conn.assigns[:current_user] do
      Hexpm.Accounts.Users.link_github_from_id(conn.assigns[:current_user], github_user_id)

      conn
      |> put_flash(:info, account_linked_message())
      |> redirect_return(conn.assigns[:current_user], conn.params["return"])
    else
      with {:ok, %{token: token}} = generate_single_use_token(github_user_id) do
        case Hexpm.Accounts.Users.get(github_email) do
          nil ->
            conn
            |> put_flash(:info, "Create a hex.pm account to link to your GitHub account")
            |> redirect(to: Routes.signup_path(conn, :show, token: token))

          _user ->
            conn
            |> put_flash(
              :info,
              "This email already has a Hex.pm account, sign in to link accounts"
            )
            |> redirect(to: Routes.login_path(conn, :show, token: token))
        end
      end
    end
  end

  defp forward_to_login_or_sign_up(conn, user, _, _), do: login(conn, user)

  defp generate_single_use_token(github_user_id),
    do: Hexpm.Accounts.Users.create_github_merge_token(github_user_id)

  ## Login stuff
  # TODO: this was duplicated from the login controller
  defp login(conn, %User{id: user_id, tfa: %{tfa_enabled: true, app_enabled: true}}) do
    conn
    |> configure_session(renew: true)
    |> put_session("tfa_user_id", %{uid: user_id, return: conn.params["return"]})
    |> redirect(to: Routes.tfa_auth_path(conn, :show))
  end

  defp login(conn, user), do: start_session(conn, user, conn.params["return"])

  def start_session(conn, user, return) do
    conn
    |> configure_session(renew: true)
    |> put_session("user_id", user.id)
    |> redirect_return(user, return)
  end

  defp redirect_return(conn, user, return) do
    path = return || Routes.user_path(conn, :show, user)
    redirect(conn, to: path)
  end
end
