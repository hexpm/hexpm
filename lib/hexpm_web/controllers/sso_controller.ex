defmodule HexpmWeb.SSOController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Error
  alias HexpmWeb.Plugs.Attack

  plug :put_no_store
  plug :require_sso_available
  plug :requires_login when action in [:link, :confirm_link, :cancel_link]
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
      {conn, discovery_opts} = take_discovery_options(conn, organization)

      with {:ok, return_path, opts} <- initiation_options(conn, organization, params),
           opts = with_discovery_options(opts, discovery_opts),
           {:ok, transaction, uri} <-
             SSO.start_login(organization, return_path, callback_url(), opts) do
        conn
        |> remember_sso_state(transaction.raw_state)
        |> redirect(external: uri)
      else
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

  def discover(conn, _params) do
    render_discovery(conn)
  end

  def submit_discovery(conn, %{"email" => email}) do
    with :ok <- allow_discovery_ip(conn),
         {:ok, domain_name} <- SSO.discovery_domain(email),
         :ok <- allow_discovery_domain(conn, domain_name) do
      case SSO.discover_organizations(domain_name) do
        [] ->
          render_discovery(conn, result: :none)

        [organization] ->
          begin_discovery_login(conn, organization, domain_name)

        organizations ->
          render(conn, "choose.html",
            title: "Choose your organization",
            container: "container page page-xs",
            organizations: organizations,
            domain: domain_name
          )
      end
    else
      {:error, :rate_limited} ->
        discovery_rate_limited(conn)

      {:error, _reason} ->
        render_discovery(conn, result: :none)
    end
  end

  def submit_discovery(conn, _params) do
    render_discovery(conn, result: :none)
  end

  def choose_discovery(conn, %{"domain" => value, "organization" => name}) do
    with :ok <- allow_discovery_ip(conn),
         {:ok, domain_name} <- SSO.canonical_domain(value),
         :ok <- allow_discovery_domain(conn, domain_name),
         %{} = organization <-
           Enum.find(SSO.discover_organizations(domain_name), &(&1.name == name)) do
      begin_discovery_login(conn, organization, domain_name)
    else
      {:error, :rate_limited} -> discovery_rate_limited(conn)
      _other -> render_discovery(conn, result: :none)
    end
  end

  def choose_discovery(conn, _params) do
    render_discovery(conn, result: :none)
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

  # Hand off to the organization route instead of redirecting to the provider
  # here. A form submission carries the page's form-action policy through every
  # redirect it follows, including same-origin hops, and the discovery page
  # cannot name the provider origin because the organization is only known once
  # the address is submitted. Rendering the hand-off ends the submission, so the
  # organization route runs as a fresh navigation.
  defp begin_discovery_login(conn, organization, domain_name) do
    conn
    |> put_session("sso_discovery_domain", domain_name)
    |> render("redirect.html",
      title: "Taking you to your provider",
      container: "container page page-xs",
      start_path: ~p"/sso/org/#{organization}"
    )
  end

  # Third-party initiation wins, it carries its own validated entrypoint.
  defp with_discovery_options(opts, discovery_opts) do
    if Keyword.has_key?(opts, :entrypoint), do: opts, else: opts ++ discovery_opts
  end

  defp take_discovery_options(conn, organization) do
    case get_session(conn, "sso_discovery_domain") do
      nil ->
        {conn, []}

      domain_name ->
        conn = delete_session(conn, "sso_discovery_domain")
        eligible = SSO.discover_organizations(domain_name)

        if Enum.any?(eligible, &(&1.id == organization.id)) do
          {conn, [entrypoint: "discovery", domain: domain_name]}
        else
          {conn, []}
        end
    end
  end

  defp allow_discovery_ip(conn) do
    case Attack.sso_discovery_ip_throttle(conn.remote_ip) do
      {:allow, _data} -> :ok
      {:block, _data} -> {:error, :rate_limited}
    end
  end

  defp allow_discovery_domain(conn, domain_name) do
    case Attack.sso_discovery_domain_throttle(
           SSO.throttle_hash(domain_name),
           conn.remote_ip
         ) do
      {:allow, _data} -> :ok
      {:block, _data} -> {:error, :rate_limited}
    end
  end

  defp discovery_rate_limited(conn) do
    conn
    |> put_status(:too_many_requests)
    |> text("Too many SSO discovery attempts. Try again later.")
  end

  defp render_discovery(conn, opts \\ []) do
    render(conn, "discover.html",
      title: "Organization SSO",
      container: "container page page-xs",
      result: Keyword.get(opts, :result)
    )
  end

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
           SSO.complete_callback(
             transaction,
             claims,
             conn.assigns.current_user,
             audit_data(conn),
             automatic_linking: fn ->
               allow_automatic_linking?(conn, transaction, claims)
             end
           ) do
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
            SSO.record_failure(transaction.connection, :link, reason, user)

            conn
            |> delete_session("pending_sso_link")
            |> put_flash(:error, sso_link_error_message(reason))
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

  def confirm(conn, _params) do
    case pending_confirmation(conn) do
      %{confirmation_verified_at: %DateTime{}} = transaction ->
        continue_verified_confirmation(conn, transaction)

      nil ->
        if conn.assigns.current_user do
          redirect(conn, to: ~p"/users/#{conn.assigns.current_user}")
        else
          conn
          |> delete_session("pending_sso_confirmation")
          |> put_flash(:error, "The SSO confirmation request is no longer valid.")
          |> redirect(to: ~p"/login")
        end

      transaction ->
        render_confirmation(conn, transaction)
    end
  end

  def submit_confirmation(conn, %{"code" => code}) do
    case pending_confirmation_session(conn) do
      %{"transaction_id" => transaction_id, "capability" => capability} ->
        case SSO.confirm_link_code(
               transaction_id,
               capability,
               code,
               conn.assigns.current_user,
               audit_data(conn)
             ) do
          {:ok, {:confirmed, _identity, user, organization, return_path}} ->
            conn
            |> cancel_pending_sso_login()
            |> delete_session("pending_sso_confirmation")
            |> delete_session("pending_sso_login")
            |> delete_session("tfa_user_id")
            |> HexpmWeb.Plugs.Sudo.clear_sudo_authentication()
            |> start_session_internal(user)
            |> put_flash(:info, "Organization SSO has been connected to your Hexpm account.")
            |> redirect(
              to:
                SSO.allowed_return_path(organization, return_path) ||
                  ~p"/users/#{user}"
            )

          {:ok, {:tfa_required, user, organization, return_path, confirmation_verified_at}} ->
            return_path =
              SSO.allowed_return_path(organization, return_path) ||
                ~p"/users/#{user}"

            authenticated_at =
              confirmation_verified_at
              |> DateTime.to_naive()
              |> NaiveDateTime.to_iso8601()

            conn
            |> cancel_pending_sso_login()
            |> delete_session("pending_sso_login")
            |> HexpmWeb.Plugs.Sudo.clear_sudo_authentication()
            |> start_tfa_session(user, return_path,
              preserve_pending_sso_confirmation: true,
              authenticated_at: authenticated_at
            )
            |> put_flash(
              :info,
              "Enter your personal Hexpm two-factor authentication code to finish connecting organization SSO."
            )
            |> redirect(to: ~p"/tfa")

          {:error, :confirmation_code_invalid} ->
            conn
            |> put_flash(:error, "The confirmation code was not valid.")
            |> confirm(%{})

          {:error, _reason} ->
            conn
            |> delete_session("pending_sso_confirmation")
            |> put_flash(:error, "The SSO confirmation request is no longer valid.")
            |> redirect(to: ~p"/login")
        end

      _other ->
        confirm(conn, %{})
    end
  end

  def submit_confirmation(conn, _params), do: confirm(conn, %{})

  def resend_confirmation(conn, _params) do
    case pending_confirmation(conn) do
      nil ->
        confirm(conn, %{})

      transaction ->
        %{"capability" => capability} = pending_confirmation_session(conn)

        if allow_automatic_linking?(conn, transaction, %{
             subject: transaction.subject,
             email: transaction.provider_email
           }) do
          case SSO.resend_confirmation(
                 transaction.id,
                 capability,
                 conn.assigns.current_user
               ) do
            {:ok, :sent} ->
              conn
              |> put_flash(:info, "A new confirmation code has been sent.")
              |> redirect(to: ~p"/sso/confirm")

            {:error, :confirmation_sends_exhausted} ->
              conn
              |> put_flash(:error, "The maximum number of confirmation codes has been sent.")
              |> render_confirmation(transaction)

            {:error, _reason} ->
              conn
              |> delete_session("pending_sso_confirmation")
              |> put_flash(:error, "The SSO confirmation request is no longer valid.")
              |> redirect(to: ~p"/login")
          end
        else
          conn
          |> put_status(:too_many_requests)
          |> put_flash(:error, "A new confirmation code could not be sent. Try again later.")
          |> render_confirmation(transaction)
        end
    end
  end

  def cancel_confirmation(conn, _params) do
    case pending_confirmation_session(conn) do
      %{"transaction_id" => transaction_id, "capability" => capability} ->
        SSO.cancel_confirmation(transaction_id, capability)

      _other ->
        :ok
    end

    conn
    |> delete_session("pending_sso_confirmation")
    |> put_flash(:info, "The SSO account link was cancelled.")
    |> redirect(to: ~p"/login")
  end

  def continue_login(conn, _params) do
    case pending_login(conn) do
      nil ->
        if conn.assigns.current_user do
          redirect(conn, to: ~p"/users/#{conn.assigns.current_user}")
        else
          conn
          |> delete_session("pending_sso_login")
          |> put_flash(:error, "The SSO login request is no longer valid.")
          |> redirect(to: ~p"/login")
        end

      transaction ->
        render(conn, "continue.html",
          title: "Continue with organization SSO",
          container: "container page page-xs",
          organization: transaction.connection.organization
        )
    end
  end

  def complete_login(conn, _params) do
    case pending_login_session(conn) do
      %{"transaction_id" => transaction_id, "capability" => capability} ->
        case SSO.complete_pending_login(
               transaction_id,
               capability,
               conn.assigns.current_user,
               audit_data(conn)
             ) do
          {:ok, {:login, user, organization, return_path}} ->
            conn
            |> cancel_pending_sso_confirmation()
            |> delete_session("pending_sso_confirmation")
            |> delete_session("pending_sso_login")
            |> delete_session("tfa_user_id")
            |> HexpmWeb.Plugs.Sudo.clear_sudo_authentication()
            |> start_session_internal(user)
            |> redirect(
              to:
                SSO.allowed_return_path(organization, return_path) ||
                  ~p"/users/#{user}"
            )

          {:error, _reason} ->
            conn
            |> delete_session("pending_sso_login")
            |> put_flash(:error, "The SSO login request is no longer valid.")
            |> redirect(to: ~p"/login")
        end

      _other ->
        continue_login(conn, %{})
    end
  end

  def cancel_login(conn, _params) do
    conn
    |> cancel_pending_sso_login()
    |> delete_session("pending_sso_login")
    |> put_flash(:info, "The SSO login was cancelled.")
    |> redirect(to: ~p"/login")
  end

  defp handle_callback_result(conn, transaction, :test) do
    organization = transaction.connection.organization

    conn
    |> put_flash(:info, "SSO connection test succeeded.")
    |> redirect(to: ~p"/dashboard/orgs/#{organization}/sso")
  end

  defp handle_callback_result(conn, _transaction, {:link, transaction_id, token, _return_path}) do
    conn
    |> cancel_pending_sso_confirmation()
    |> cancel_pending_sso_login()
    |> delete_session("pending_sso_confirmation")
    |> delete_session("pending_sso_login")
    |> delete_session("tfa_user_id")
    |> put_session("pending_sso_link", %{"transaction_id" => transaction_id, "token" => token})
    |> redirect(to: ~p"/login?return=/sso/link")
  end

  defp handle_callback_result(
         conn,
         _transaction,
         {:confirm, transaction_id, capability, _return_path}
       ) do
    conn
    |> cancel_pending_sso_confirmation()
    |> cancel_pending_sso_login()
    |> delete_session("pending_sso_link")
    |> delete_session("pending_sso_login")
    |> delete_session("tfa_user_id")
    |> put_session("pending_sso_confirmation", %{
      "transaction_id" => transaction_id,
      "capability" => capability
    })
    |> redirect(to: ~p"/sso/confirm")
  end

  defp handle_callback_result(
         conn,
         _transaction,
         {:continue, transaction_id, capability, _return_path}
       ) do
    conn
    |> cancel_pending_sso_confirmation()
    |> cancel_pending_sso_login()
    |> delete_session("pending_sso_confirmation")
    |> delete_session("pending_sso_link")
    |> delete_session("tfa_user_id")
    |> put_session("pending_sso_login", %{
      "transaction_id" => transaction_id,
      "capability" => capability
    })
    |> redirect(to: ~p"/sso/continue")
  end

  defp handle_callback_result(
         conn,
         transaction,
         {:login, user, return_path}
       ) do
    conn
    |> cancel_pending_sso_confirmation()
    |> cancel_pending_sso_login()
    |> delete_session("pending_sso_confirmation")
    |> delete_session("pending_sso_login")
    |> delete_session("tfa_user_id")
    |> HexpmWeb.Plugs.Sudo.clear_sudo_authentication()
    |> start_session_internal(user)
    |> redirect(
      to:
        SSO.allowed_return_path(transaction.connection.organization, return_path) ||
          ~p"/users/#{user}"
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

  defp pending_confirmation(conn) do
    case pending_confirmation_session(conn) do
      %{"transaction_id" => transaction_id, "capability" => capability} ->
        SSO.get_pending_confirmation(transaction_id, capability)

      _other ->
        nil
    end
  end

  defp pending_confirmation_session(conn) do
    get_session(conn, "pending_sso_confirmation")
  end

  defp pending_login(conn) do
    case pending_login_session(conn) do
      %{"transaction_id" => transaction_id, "capability" => capability} ->
        SSO.get_pending_login(transaction_id, capability)

      _other ->
        nil
    end
  end

  defp pending_login_session(conn) do
    get_session(conn, "pending_sso_login")
  end

  defp render_confirmation(conn, transaction) do
    render(conn, "confirm.html",
      title: "Confirm organization SSO",
      container: "container page page-xs",
      organization: transaction.connection.organization
    )
  end

  defp continue_verified_confirmation(conn, transaction) do
    case {get_session(conn, "tfa_user_id"), pending_confirmation_session(conn)} do
      {%{"uid" => uid, "at" => at, "origin" => "sso_confirmation"},
       %{"transaction_id" => transaction_id, "capability" => capability}}
      when uid == transaction.candidate_user_id and transaction_id == transaction.id ->
        if HexpmWeb.Session.TTL.within?(at, minute: 15) do
          redirect(conn, to: ~p"/tfa")
        else
          SSO.cancel_confirmation(transaction_id, capability)

          conn
          |> delete_session("pending_sso_confirmation")
          |> delete_session("tfa_user_id")
          |> put_flash(:error, "The SSO confirmation request is no longer valid.")
          |> redirect(to: ~p"/login")
        end

      _other ->
        conn
        |> cancel_pending_sso_confirmation()
        |> delete_session("pending_sso_confirmation")
        |> delete_session("tfa_user_id")
        |> put_flash(:error, "The SSO confirmation request is no longer valid.")
        |> redirect(to: ~p"/login")
    end
  end

  defp allow_automatic_linking?(conn, transaction, claims) do
    with subject when is_binary(subject) <- claims[:subject],
         email when is_binary(email) <- claims[:email] do
      organization_id = transaction.connection.organization.id
      subject_hash = SSO.throttle_hash(subject)
      email_hash = SSO.throttle_hash(String.downcase(email))

      [
        Attack.sso_link_ip_throttle(conn.remote_ip),
        Attack.sso_link_organization_throttle(organization_id),
        Attack.sso_link_subject_throttle(subject_hash),
        Attack.sso_link_email_throttle(email_hash)
      ]
      |> Enum.all?(&match?({:allow, _data}, &1))
    else
      _other -> false
    end
  end

  defp callback_url, do: url(~p"/sso/callback")

  defp start_error_message(:connection_disabled), do: "SSO is not enabled for that organization."
  defp start_error_message(:not_configured), do: "SSO is not configured for that organization."
  defp start_error_message(_reason), do: "SSO login could not be started."
end
