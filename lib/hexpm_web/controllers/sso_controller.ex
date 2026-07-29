defmodule HexpmWeb.SSOController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Error
  alias HexpmWeb.Plugs.Attack

  plug :put_no_store
  plug :require_sso_available
  plug :requires_login when action in [:start, :link, :confirm_link, :cancel_link]
  plug :rate_limit_callback when action in [:callback]

  defp require_sso_available(conn, _opts) do
    if SSO.available?() do
      conn
    else
      conn
      |> not_found()
      |> halt()
    end
  end

  def start(conn, %{"organization" => name} = params) do
    organization = Organizations.get(name)

    if organization && SSO.enabled?(organization) && allow_start?(conn, organization) do
      with {:ok, return_path, opts} <- initiation_options(conn, organization, params),
           {:ok, transaction, uri} <-
             SSO.start_login(
               organization,
               conn.assigns.current_user,
               return_path,
               callback_url(),
               opts
             ) do
        conn
        |> remember_sso_state(transaction.raw_state)
        |> redirect(external: uri)
      else
        {:error, reason} ->
          conn
          |> put_flash(:error, start_error_message(reason))
          |> redirect(to: ~p"/dashboard")
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

  defp initiation_options(conn, organization, params) do
    with {:ok, query} <- decode_initiation_query(conn.query_string),
         :ok <- reject_duplicate_initiation_parameters(query) do
      recognized = Enum.filter(query, &(elem(&1, 0) in ~w(iss login_hint target_link_uri)))

      if recognized == [] do
        {:ok, params["return"], []}
      else
        connection = SSO.get_connection(organization)
        values = Map.new(recognized)

        with %{} <- connection,
             true <- values["iss"] == connection.issuer,
             {:ok, login_hint} <- validate_login_hint(values["login_hint"]),
             {:ok, return_path} <-
               validate_target_link_uri(organization, values["target_link_uri"]) do
          {:ok, return_path,
           [
             entrypoint: "third_party",
             login_hint: login_hint
           ]}
        else
          _other -> {:error, :invalid_third_party_initiation}
        end
      end
    end
  end

  defp decode_initiation_query(""), do: {:ok, []}

  defp decode_initiation_query(query_string) do
    {:ok, Enum.to_list(URI.query_decoder(query_string))}
  rescue
    _exception -> {:error, :invalid_third_party_initiation}
  end

  defp reject_duplicate_initiation_parameters(query) do
    duplicate? =
      query
      |> Enum.filter(&(elem(&1, 0) in ~w(iss login_hint target_link_uri)))
      |> Enum.frequencies_by(&elem(&1, 0))
      |> Enum.any?(fn {_key, count} -> count > 1 end)

    if duplicate?, do: {:error, :invalid_third_party_initiation}, else: :ok
  end

  defp validate_login_hint(nil), do: {:ok, nil}
  defp validate_login_hint(""), do: {:ok, nil}

  defp validate_login_hint(login_hint)
       when is_binary(login_hint) and byte_size(login_hint) <= 320 do
    if String.valid?(login_hint),
      do: {:ok, login_hint},
      else: {:error, :invalid_third_party_initiation}
  end

  defp validate_login_hint(_login_hint), do: {:error, :invalid_third_party_initiation}

  defp validate_target_link_uri(_organization, nil), do: {:ok, nil}

  defp validate_target_link_uri(organization, target_link_uri)
       when is_binary(target_link_uri) and byte_size(target_link_uri) <= 2_048 do
    configured = URI.parse(Application.fetch_env!(:hexpm, :email_base_url))
    target = URI.parse(target_link_uri)

    with true <- same_origin?(configured, target),
         nil <- target.userinfo,
         nil <- target.fragment,
         path when is_binary(path) <- target.path,
         relative = path <> if(target.query, do: "?" <> target.query, else: ""),
         return_path when is_binary(return_path) <-
           SSO.allowed_return_path(organization, relative) do
      {:ok, return_path}
    else
      _other -> {:error, :invalid_third_party_initiation}
    end
  end

  defp validate_target_link_uri(_organization, _target_link_uri),
    do: {:error, :invalid_third_party_initiation}

  defp same_origin?(left, right) do
    left.scheme in ["http", "https"] and left.scheme == right.scheme and
      is_binary(left.host) and is_binary(right.host) and
      String.downcase(left.host) == String.downcase(right.host) and
      valid_authority?(right.authority) and
      effective_port(left) == effective_port(right)
  end

  defp valid_authority?(authority) when is_binary(authority) do
    not String.contains?(authority, ["%", "\\", "\r", "\n", "\t"])
  end

  defp valid_authority?(_authority), do: false

  defp effective_port(%URI{port: port}) when is_integer(port), do: port
  defp effective_port(%URI{scheme: "http"}), do: 80
  defp effective_port(%URI{scheme: "https"}), do: 443
  defp effective_port(_uri), do: nil

  defp put_no_store(conn, _opts) do
    put_resp_header(conn, "cache-control", "no-store")
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
    case bound_transaction(conn, state) do
      nil -> callback_error(conn, nil, :invalid_state)
      transaction -> abandon(conn, transaction, :authorization, :provider_error)
    end
  end

  def callback(conn, %{"state" => state, "code" => code})
      when is_binary(code) and byte_size(code) <= 4_096 do
    case bound_transaction(conn, state) do
      nil ->
        callback_error(conn, nil, :invalid_state)

      transaction ->
        conn
        |> forget_sso_state(state)
        |> exchange_and_complete(transaction, code)
    end
  end

  def callback(conn, params) do
    case bound_transaction(conn, params["state"]) do
      nil -> callback_error(conn, nil, :invalid_response)
      transaction -> abandon(conn, transaction, :callback, :invalid_response)
    end
  end

  defp exchange_and_complete(conn, transaction, code) do
    with {:ok, user, user_session_id} <- account_session(conn, transaction),
         {:ok, claims} <- SSO.exchange_code(transaction, code, callback_url()),
         {:ok, result} <-
           SSO.complete_callback(transaction, claims, user, user_session_id, audit_data(conn)) do
      handle_callback_result(conn, transaction, result)
    else
      # account_session/2 and complete_callback/5 record their own failures.
      {:error, :account_session_required} ->
        account_session_required(conn)

      {:error, %Error{} = error} ->
        abandon(conn, transaction, error.stage, error.code)

      {:error, reason} ->
        callback_error(conn, transaction, reason)
    end
  end

  defp bound_transaction(conn, state) do
    if is_binary(state) and valid_sso_state?(conn, state) do
      SSO.get_transaction_by_state(state)
    end
  end

  # The provider never got past authorization, or returned something unusable.
  # Consume the transaction so the still-valid authorization code and the state
  # left in the browser cannot be replayed.
  defp abandon(conn, transaction, stage, code) do
    SSO.abandon_login(transaction, stage, code)
    callback_error(conn, transaction, code)
  end

  # The account session is what the callback authenticates against, so losing it
  # mid-flow ends the attempt. Bouncing through login and resuming would drop the
  # provider's state and code, and SSO must never mint a session to recover.
  defp account_session(conn, transaction) do
    case {conn.assigns.current_user, conn.assigns.current_session} do
      {%{} = user, %{id: user_session_id}} ->
        {:ok, user, user_session_id}

      _other ->
        SSO.abandon_login(transaction, :callback, :account_session_required)
        {:error, :account_session_required}
    end
  end

  defp account_session_required(conn) do
    conn
    |> put_flash(
      :error,
      "You were signed out before the organization SSO login finished. Sign in and try again."
    )
    |> redirect(to: ~p"/login")
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
        |> redirect(to: ~p"/dashboard")

      transaction ->
        if transaction.user_id == conn.assigns.current_user.id do
          render(conn, "link.html",
            title: "Connect organization SSO",
            container: "container page page-xs",
            organization: transaction.connection.organization,
            provider_email: transaction.provider_email
          )
        else
          conn
          |> delete_session("pending_sso_link")
          |> put_flash(:error, sso_link_error_message(:session_user_mismatch))
          |> redirect(to: ~p"/dashboard")
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

        case SSO.complete_link(
               transaction.id,
               token,
               user,
               conn.assigns.current_session.id,
               audit_data(conn)
             ) do
          {:ok, {_identity, _org_session}} ->
            organization = transaction.connection.organization

            conn
            |> delete_session("pending_sso_link")
            |> put_flash(:info, "Organization SSO has been connected to your Hexpm account.")
            |> redirect(
              to:
                SSO.allowed_return_path(organization, transaction.return_path) ||
                  ~p"/dashboard/orgs/#{organization}"
            )

          {:error, reason} ->
            SSO.record_failure(transaction.connection, :link, reason, user)

            conn
            |> delete_session("pending_sso_link")
            |> put_flash(:error, sso_link_error_message(reason))
            |> redirect(to: ~p"/dashboard")
        end
    end
  end

  def cancel_link(conn, _params) do
    transaction = pending_link(conn)

    if transaction do
      %{"token" => token} = get_session(conn, "pending_sso_link")
      SSO.cancel_link(transaction.id, token)
    end

    conn
    |> delete_session("pending_sso_link")
    |> put_flash(:info, "The SSO account link was cancelled.")
    |> redirect(to: ~p"/users/#{conn.assigns.current_user}")
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
    |> redirect(to: ~p"/sso/link")
  end

  defp handle_callback_result(conn, transaction, {:login, _user, _org_session, return_path}) do
    organization = transaction.connection.organization

    conn
    |> put_flash(:info, "You are authenticated to #{organization.name}.")
    |> redirect(
      to:
        SSO.allowed_return_path(organization, return_path) || ~p"/dashboard/orgs/#{organization}"
    )
  end

  # Rendering only. Every caller has already recorded its own diagnostic, either
  # through `abandon/4` or inside the context.
  defp callback_error(conn, transaction, code) do
    destination =
      cond do
        transaction && transaction.kind == "test" ->
          ~p"/dashboard/orgs/#{transaction.connection.organization}/sso"

        logged_in?(conn) ->
          ~p"/dashboard"

        true ->
          ~p"/login"
      end

    conn
    |> put_flash(:error, sso_callback_error_message(code))
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

  defp start_error_message(:not_member),
    do: "You are not a member of that organization. Ask an administrator to add you."

  defp start_error_message(_reason), do: "SSO login could not be started."
end
