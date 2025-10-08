defmodule HexpmWeb.AuthController do
  use HexpmWeb, :controller
  plug Ueberauth

  alias Hexpm.Accounts.{Auth, Users, UserProviders}

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with GitHub.")
    |> redirect(to: ~p"/login")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    provider = to_string(auth.provider)
    provider_uid = to_string(auth.uid)

    if logged_in?(conn) do
      # User is already logged in - try to link this provider
      link_provider_to_user(conn, provider, provider_uid, auth.info.email)
    else
      # Not logged in - check if provider exists or create new user
      case Auth.provider_auth(provider, provider_uid) do
        {:ok, %{user: user}} ->
          # Existing user with this provider - log them in
          handle_existing_user_login(conn, user)

        :error ->
          # No user found with this provider
          handle_new_provider(
            conn,
            provider,
            provider_uid,
            auth.info.email,
            auth.info.name,
            auth.info.nickname
          )
      end
    end
  end

  defp handle_existing_user_login(conn, user) do
    if User.tfa_enabled?(user) do
      conn
      |> configure_session(renew: true)
      |> put_session("tfa_user_id", %{uid: user.id, return: conn.params["return"]})
      |> redirect(to: ~p"/tfa")
    else
      conn
      |> configure_session(renew: true)
      |> put_session("user_id", user.id)
      |> redirect(to: conn.params["return"] || ~p"/users/#{user}")
    end
  end

  defp handle_new_provider(
         conn,
         provider,
         provider_uid,
         provider_email,
         provider_name,
         provider_nickname
       ) do
    # Check if email matches existing user
    case Users.get_email(provider_email, [:user]) do
      nil ->
        # New user - store OAuth data in session and redirect to username selection
        store_oauth_in_session(
          conn,
          provider,
          provider_uid,
          provider_email,
          provider_name,
          provider_nickname
        )

      %{user: _existing_user} ->
        # Email exists - show error asking to log in first
        conn
        |> put_flash(
          :error,
          "An account with email #{provider_email} already exists. Please log in first, then connect your GitHub account from the dashboard."
        )
        |> redirect(to: ~p"/login")
    end
  end

  defp link_provider_to_user(conn, provider, provider_uid, provider_email) do
    user = conn.assigns.current_user

    case UserProviders.create(user, provider, provider_uid, provider_email, %{},
           audit: audit_data(conn)
         ) do
      {:ok, _user_provider} ->
        conn
        |> put_flash(:info, "GitHub account successfully connected.")
        |> redirect(to: ~p"/dashboard/security")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to connect GitHub account.")
        |> redirect(to: ~p"/dashboard/security")
    end
  end

  defp store_oauth_in_session(
         conn,
         provider,
         provider_uid,
         provider_email,
         provider_name,
         provider_nickname
       ) do
    conn
    |> put_session("pending_oauth", %{
      provider: provider,
      provider_uid: provider_uid,
      provider_email: provider_email,
      provider_name: provider_name,
      provider_nickname: provider_nickname
    })
    |> redirect(to: ~p"/auth/complete-signup")
  end

  def show_username_form(conn, _params) do
    case get_session(conn, "pending_oauth") do
      nil ->
        conn
        |> put_flash(:error, "Session expired. Please try signing up again.")
        |> redirect(to: ~p"/signup")

      oauth_data ->
        suggested_username =
          generate_username(oauth_data[:provider_nickname], oauth_data[:provider_email])

        render(conn, "complete_signup.html",
          suggested_username: suggested_username,
          changeset: nil,
          container: "container page page-xs"
        )
    end
  end

  def complete_signup(conn, %{"user" => %{"username" => username}}) do
    case get_session(conn, "pending_oauth") do
      nil ->
        conn
        |> put_flash(:error, "Session expired. Please try signing up again.")
        |> redirect(to: ~p"/signup")

      oauth_data ->
        create_user_from_oauth(conn, oauth_data, username)
    end
  end

  defp create_user_from_oauth(conn, oauth_data, username) do
    provider = oauth_data[:provider]
    provider_uid = oauth_data[:provider_uid]
    provider_email = oauth_data[:provider_email]
    provider_name = oauth_data[:provider_name]

    case Users.add_from_oauth_with_provider(
           username,
           provider_name,
           provider_email,
           provider,
           provider_uid,
           audit: audit_data(conn),
           confirmed?: true
         ) do
      {:ok, user} ->
        conn
        |> delete_session("pending_oauth")
        |> configure_session(renew: true)
        |> put_session("user_id", user.id)
        |> put_flash(:info, "Account created successfully!")
        |> redirect(to: ~p"/users/#{user}")

      {:error, changeset} ->
        suggested_username =
          generate_username(oauth_data[:provider_nickname], oauth_data[:provider_email])

        render(conn, "complete_signup.html",
          suggested_username: suggested_username,
          changeset: changeset,
          container: "container page page-xs"
        )
    end
  end

  defp generate_username(nickname, _email) when is_binary(nickname) and nickname != "" do
    suggested =
      nickname
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_\-\.]/, "")
      |> String.slice(0, 20)

    if byte_size(suggested) >= 3, do: suggested, else: nil
  end

  defp generate_username(_nickname, email) when is_binary(email) do
    suggested =
      email
      |> String.split("@")
      |> List.first()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_\-\.]/, "")
      |> String.slice(0, 20)

    if byte_size(suggested) >= 3, do: suggested, else: nil
  end

  defp generate_username(_nickname, _email), do: nil
end
