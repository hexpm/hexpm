defmodule HexpmWeb.SSOController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Error
  alias HexpmWeb.Plugs.Attack

  plug :requires_login when action in [:link, :confirm_link, :cancel_link]
  plug :rate_limit_callback when action in [:callback]

  def start(conn, %{"organization" => name} = params) do
    organization = Organizations.get(name)
    return_path = params["return"]

    if organization && SSO.enabled?(organization) && allow_start?(conn, organization) do
      case SSO.start_login(organization, return_path, callback_url()) do
        {:ok, transaction, uri} ->
          conn
          |> remember_sso_state(transaction.raw_state)
          |> redirect(external: uri)

        {:error, reason} ->
          conn
          |> put_flash(:error, start_error_message(reason))
          |> redirect(to: ~p"/login")
      end
    else
      if organization && SSO.enabled?(organization) do
        conn
        |> put_status(:too_many_requests)
        |> text("Too many SSO login attempts. Try again later.")
      else
        not_found(conn)
      end
    end
  end

  defp allow_start?(conn, organization) do
    match?({:allow, _data}, Attack.sso_start_ip_throttle(conn.remote_ip)) and
      match?(
        {:allow, _data},
        Attack.sso_start_organization_throttle(organization.id, conn.remote_ip)
      )
  end

  defp rate_limit_callback(conn, _opts) do
    case Attack.sso_callback_ip_throttle(conn.remote_ip) do
      {:allow, _data} ->
        conn

      {:block, _data} ->
        conn
        |> put_status(:too_many_requests)
        |> text("Too many SSO callback attempts. Try again later.")
        |> halt()
    end
  end

  def callback(conn, %{"state" => state, "error" => _provider_error}) do
    if valid_sso_state?(conn, state) do
      case SSO.get_transaction_by_state(state) do
        nil -> callback_error(conn, nil, :authorization, :invalid_state)
        transaction -> callback_error(conn, transaction, :authorization, :provider_error)
      end
    else
      callback_error(conn, nil, :authorization, :invalid_state)
    end
  end

  def callback(conn, %{"state" => state, "code" => code})
      when is_binary(code) and byte_size(code) <= 4_096 do
    with true <- valid_sso_state?(conn, state),
         %{} = transaction <- SSO.get_transaction_by_state(state),
         {:ok, claims} <- SSO.exchange_code(transaction, code, callback_url()),
         {:ok, result} <-
           SSO.complete_callback(transaction, claims, conn.assigns.current_user, audit_data(conn)) do
      conn
      |> forget_sso_state(state)
      |> handle_callback_result(transaction, result)
    else
      false -> callback_error(conn, nil, :callback, :invalid_state)
      nil -> callback_error(conn, nil, :callback, :invalid_state)
      {:error, %Error{} = error} -> callback_error(conn, state, error.stage, error.code)
      {:error, reason} -> callback_error(conn, state, :callback, reason)
    end
  end

  def callback(conn, params) do
    transaction =
      if params["state"] && valid_sso_state?(conn, params["state"]) do
        SSO.get_transaction_by_state(params["state"])
      end

    callback_error(conn, transaction, :callback, :invalid_response)
  end

  def link(conn, _params) do
    case pending_link(conn) do
      nil ->
        conn
        |> delete_session("pending_sso_link")
        |> put_flash(
          :error,
          "The SSO account-link request has expired. Start again from the organization login link."
        )
        |> redirect(to: ~p"/login")

      transaction ->
        if transaction.user_id == conn.assigns.current_user.id do
          render(conn, "link.html",
            title: "Connect organization SSO",
            container: "container page page-xs",
            organization: transaction.connection.organization,
            provider_email: transaction.provider_email
          )
        else
          redirect(conn, to: ~p"/login?return=/sso/link")
        end
    end
  end

  def confirm_link(conn, _params) do
    case pending_link(conn) do
      nil ->
        link(conn, %{})

      transaction ->
        %{"token" => token} = get_session(conn, "pending_sso_link")
        user = Hexpm.Repo.preload(conn.assigns.current_user, :emails)

        case SSO.complete_link(transaction.id, token, user, audit_data(conn)) do
          {:ok, _identity} ->
            conn
            |> delete_session("pending_sso_link")
            |> put_flash(:info, "Organization SSO has been connected to your Hexpm account.")
            |> redirect(
              to:
                SSO.allowed_return_path(
                  transaction.connection.organization,
                  transaction.return_path
                ) ||
                  ~p"/dashboard/orgs/#{transaction.connection.organization}"
            )

          {:error, reason} ->
            SSO.record_failure(transaction.connection, :link, reason)

            conn
            |> delete_session("pending_sso_link")
            |> put_flash(:error, link_error_message(reason))
            |> redirect(to: ~p"/login")
        end
    end
  end

  def cancel_link(conn, _params) do
    transaction = pending_link(conn)

    if transaction do
      %{"token" => token} = get_session(conn, "pending_sso_link")
      SSO.cancel_link(transaction.id, token)
    end

    conn =
      conn
      |> delete_session("pending_sso_link")
      |> put_flash(:info, "The SSO account link was cancelled.")

    redirect(conn, to: ~p"/users/#{conn.assigns.current_user}")
  end

  defp handle_callback_result(conn, transaction, :test) do
    organization = transaction.connection.organization

    conn
    |> put_flash(:info, "SSO connection test succeeded.")
    |> redirect(to: ~p"/dashboard/orgs/#{organization}/sso")
  end

  defp handle_callback_result(conn, _transaction, {:link, transaction_id, token, _return_path}) do
    conn
    |> put_session("pending_sso_link", %{"transaction_id" => transaction_id, "token" => token})
    |> redirect(to: ~p"/login?return=/sso/link")
  end

  defp handle_callback_result(
         conn,
         transaction,
         {:login, user, _notify_email_mismatch?, _provider_email, return_path}
       ) do
    conn
    |> HexpmWeb.Plugs.Sudo.clear_sudo_authentication()
    |> start_session_internal(user)
    |> redirect(
      to:
        SSO.allowed_return_path(transaction.connection.organization, return_path) ||
          ~p"/dashboard/orgs/#{transaction.connection.organization}"
    )
  end

  defp callback_error(conn, transaction_or_state, stage, code) do
    transaction =
      case transaction_or_state do
        %Hexpm.Accounts.SSO.Transaction{} = transaction -> transaction
        state when is_binary(state) -> SSO.get_transaction_by_state(state)
        _other -> nil
      end

    if transaction do
      SSO.record_failure(transaction.connection, stage, code)
    end

    destination =
      if transaction && transaction.kind == "test" do
        ~p"/dashboard/orgs/#{transaction.connection.organization}/sso"
      else
        ~p"/login"
      end

    conn
    |> put_flash(:error, "SSO authentication failed (#{code}).")
    |> redirect(to: destination)
  end

  defp pending_link(conn) do
    case get_session(conn, "pending_sso_link") do
      %{"transaction_id" => transaction_id, "token" => token} ->
        SSO.get_pending_link(transaction_id, token)

      _other ->
        nil
    end
  end

  defp callback_url, do: url(~p"/sso/callback")

  defp start_error_message(:connection_disabled), do: "SSO is not enabled for that organization."
  defp start_error_message(:not_configured), do: "SSO is not configured for that organization."
  defp start_error_message(_reason), do: "SSO login could not be started."

  defp link_error_message(:not_member),
    do:
      "This Hexpm account is not a member of the organization. Ask an administrator to add it before retrying SSO."

  defp link_error_message({:identity_conflict, _changeset}),
    do: "That SSO identity or Hexpm account is already linked."

  defp link_error_message(_reason),
    do: "The SSO identity could not be linked. Start the login again."
end
