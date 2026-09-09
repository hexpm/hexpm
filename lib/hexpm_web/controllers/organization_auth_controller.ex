defmodule HexpmWeb.OrganizationAuthController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.{OrganizationAuth, TFASessions, TFA}
  alias HexpmWeb.Plugs.Attack

  plug :requires_login

  def authenticate(conn, %{"organization" => name} = params) do
    user = conn.assigns.current_user
    organization = Organizations.get(name)
    return_to = safe_return_path(params["return"]) || ~p"/dashboard/orgs/#{name}"

    if organization && Organizations.get_role(organization, user) do
      case OrganizationAuth.required(user, [name], conn.assigns.current_session.id) do
        [] ->
          redirect(conn, to: return_to)

        [%{requirements: requirements}] ->
          if "tfa" in requirements do
            conn
            |> put_session(
              :tfa_return_to,
              ~p"/organizations/#{name}/authenticate?#{[return: return_to]}"
            )
            |> redirect(
              to: if(User.tfa_enabled?(user), do: ~p"/tfa/verify", else: ~p"/dashboard/security")
            )
          else
            redirect(conn, to: ~p"/sso/org/#{name}?#{[return: return_to]}")
          end
      end
    else
      not_found(conn)
    end
  end

  def verify(conn, params) do
    conn =
      if return_to = safe_return_path(params["return"]),
        do: put_session(conn, :tfa_return_to, return_to),
        else: conn

    if User.tfa_enabled?(conn.assigns.current_user),
      do: render_verification(conn),
      else: redirect(conn, to: ~p"/dashboard/security")
  end

  def verify_code(conn, %{"code" => code}) do
    user = Users.get_by_id(conn.assigns.current_user.id)
    session_data = %{"uid" => user.id, "at" => 0}
    ip_result = Attack.tfa_ip_throttle(conn.remote_ip)
    session_result = Attack.tfa_session_throttle(session_data)

    with false <- match?({:block, _}, ip_result) or match?({:block, _}, session_result),
         {:ok, user} <- verify_user(user, code),
         {:ok, :ok} <- TFASessions.record_verified!(user, conn.assigns.current_session.id) do
      complete_tfa_authorization(conn)
    else
      _ ->
        Hexpm.SecurityLog.auth_failure(conn, :tfa, :invalid_code, user_id: user.id)

        conn
        |> put_flash(:error, "2FA verification failed. Check your code or try again later.")
        |> render_verification()
    end
  end

  defp render_verification(conn) do
    conn
    |> HexpmWeb.SSOEnforcement.allow_authorization_return_form_action(
      get_session(conn, :tfa_return_to)
    )
    |> render(:verify, title: "2FA verification", container: "container page page-xs")
  end

  defp verify_user(user, code) do
    cond do
      not User.tfa_enabled?(user) ->
        {:error, :not_enrolled}

      is_binary(code) and byte_size(code) == 6 and TFA.token_valid?(user.tfa.secret, code) ->
        {:ok, user}

      is_binary(code) and byte_size(code) == 19 ->
        Users.tfa_recover(user, code)

      true ->
        {:error, :invalid_code}
    end
  end

  defp complete_tfa_authorization(conn) do
    return_to = get_session(conn, :tfa_return_to) || ~p"/dashboard/security"

    conn
    |> delete_session(:tfa_return_to)
    |> HexpmWeb.Plugs.Sudo.set_sudo_authenticated()
    |> redirect(to: return_to)
  end
end
