defmodule HexpmWeb.SSOController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Error
  alias HexpmWeb.Plugs.Attack
  alias HexpmWeb.Plugs.ContentSecurityPolicy

  plug :put_no_store
  plug :require_sso_available

  plug :requires_login
       when action in [
              :start,
              :link,
              :confirm_link,
              :cancel_link,
              :authorize,
              :authorize_organization
            ]

  # The same bar device approval sets, for the same reason: this hands a
  # capability to a session that is not the browser doing the clicking, and a
  # stolen access token is enough to ask for the page.
  plug HexpmWeb.Plugs.Sudo when action in [:authorize, :authorize_organization]

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

    if organization && SSO.reachable?(organization) && allow_start?(conn, organization) do
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
      if organization && SSO.reachable?(organization) do
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
         :ok <- SSO.maybe_expand_seats(transaction, user, claims),
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
              to: login_destination(conn, transaction, organization, transaction.return_path)
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

  @doc """
  Authenticates a session that cannot reach a browser itself.

  Everything the provider needs happens here, in a browser that is signed in as
  the same account, and the organization access lands on the session named by
  the request rather than on this one.
  """
  def authorize(conn, %{"code" => code}) do
    case SSO.get_authorization(code, conn.assigns.current_user) do
      nil ->
        expired_authorization(conn)

      authorization ->
        case SSO.authorization_status(authorization) do
          [] ->
            expired_authorization(conn)

          status ->
            if Enum.all?(status, fn {_organization, authenticated?} -> authenticated? end) do
              SSO.consume_authorization!(authorization)

              conn
              |> delete_session("sso_authorization")
              |> put_flash(:info, authorized_message(authorization, status))
              |> redirect(to: ~p"/dashboard")
            else
              conn
              |> allow_provider_form_actions(status)
              |> render("authorize.html",
                title: "Authenticate a session",
                container: "container page page-xs",
                code: code,
                session: authorization.user_session,
                organizations: status
              )
            end
        end
    end
  end

  # The code moved out of the path, so both actions can now be reached without
  # one. Say the same thing a stale code says rather than raising.
  def authorize(conn, _params), do: expired_authorization(conn)

  def authorize_organization(conn, %{"code" => code, "organization" => name}) do
    case SSO.get_authorization(code, conn.assigns.current_user) do
      nil ->
        expired_authorization(conn)

      authorization ->
        case authorized_organization(authorization, name) do
          # Already done, or never on the list. Either way the page is where the
          # answer is, and re-rendering it says nothing a second request would
          # not have said anyway.
          nil ->
            redirect(conn, to: ~p"/sso/authorize?#{[code: code]}")

          organization ->
            if allow_start?(conn, organization) do
              start_authorization(conn, authorization, organization, code)
            else
              conn
              |> put_status(:too_many_requests)
              |> text("Too many SSO login attempts. Try again later.")
            end
        end
    end
  end

  def authorize_organization(conn, %{"code" => code}) do
    redirect(conn, to: ~p"/sso/authorize?#{[code: code]}")
  end

  def authorize_organization(conn, _params), do: expired_authorization(conn)

  # Each button on the page submits to an action that redirects to that
  # organization's provider, and Chrome applies form-action to the redirect.
  defp allow_provider_form_actions(conn, status) do
    Enum.reduce(status, conn, fn
      {_organization, true}, conn ->
        conn

      {organization, false}, conn ->
        case SSO.get_connection(organization) do
          nil -> conn
          connection -> ContentSecurityPolicy.allow_form_action(conn, connection.issuer)
        end
    end)
  end

  defp start_authorization(conn, authorization, organization, code) do
    case SSO.start_login(organization, conn.assigns.current_user, nil, callback_url(),
           entrypoint: "cli",
           target_user_session_id: authorization.user_session_id
         ) do
      {:ok, transaction, uri} ->
        conn
        |> put_session("sso_authorization", code)
        |> remember_sso_state(transaction.raw_state)
        |> redirect(external: uri)

      {:error, reason} ->
        conn
        |> put_flash(:error, start_error_message(reason))
        |> redirect(to: ~p"/sso/authorize?#{[code: code]}")
    end
  end

  defp authorized_organization(authorization, name) when is_binary(name) do
    Enum.find_value(SSO.authorization_status(authorization), fn {organization, authenticated?} ->
      if organization.name == name and not authenticated?, do: organization
    end)
  end

  defp authorized_organization(_authorization, _name), do: nil

  defp expired_authorization(conn) do
    conn
    |> delete_session("sso_authorization")
    |> put_flash(
      :error,
      "That authentication request is no longer open. Run the command again for a new link."
    )
    |> redirect(to: ~p"/dashboard")
  end

  defp authorized_message(authorization, status) do
    names = status |> Enum.map(fn {organization, _} -> organization.name end) |> Enum.join(", ")
    session = authorization.user_session.name || "your session"

    "#{session} is authenticated to #{names}. You can go back to your terminal."
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
    |> redirect(to: login_destination(conn, transaction, organization, return_path))
  end

  defp login_destination(conn, transaction, organization, return_path) do
    authorization_path(conn, transaction) ||
      SSO.allowed_return_path(organization, return_path) ||
      ~p"/dashboard/orgs/#{organization}"
  end

  # An authentication a terminal asked for goes back to the page listing what is
  # left to do, not to the organization's dashboard.
  defp authorization_path(conn, %{target_user_session_id: target}) when not is_nil(target) do
    case get_session(conn, "sso_authorization") do
      code when is_binary(code) -> ~p"/sso/authorize?#{[code: code]}"
      _other -> nil
    end
  end

  defp authorization_path(_conn, _transaction), do: nil

  # Rendering only. Callers that found a transaction have already recorded their
  # diagnostic, either through `abandon/4` or inside the context. The ones that
  # pass `nil` have no connection to record it against.
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
