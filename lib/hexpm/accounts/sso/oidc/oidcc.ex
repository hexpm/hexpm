defmodule Hexpm.Accounts.SSO.OIDC.Oidcc do
  @behaviour Hexpm.Accounts.SSO.OIDC

  alias Hexpm.Accounts.SSO.{Connection, Error, OIDC, SafeURL, Transaction}
  alias Hexpm.Accounts.SSO.OIDC.{HTTPAdapter, Issuer}

  @allowed_signing_algorithms ~w(RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 EdDSA)
  @allowed_token_auth_methods ~w(client_secret_basic client_secret_post)
  @preferred_token_auth_methods [:client_secret_basic, :client_secret_post]
  @fallback_cache_seconds 3_600
  @http_timeout 5_000
  @clock_skew_seconds 60
  @logout_event "http://schemas.openid.net/event/backchannel-logout"
  @logout_token_max_age_seconds 300
  @sid_max_bytes 4096

  @impl true
  def discover(issuer) do
    with_adapter(fn ref ->
      with {:ok, _uri} <- Issuer.validate(issuer),
           {:ok, configuration, discovery_document, discovery_expires_at} <-
             load_configuration(issuer, ref),
           :ok <- validate_configuration(configuration),
           {:ok, _uri} <- SafeURL.validate(configuration.authorization_endpoint),
           {:ok, _uri} <- SafeURL.validate(configuration.token_endpoint),
           {:ok, _jwks, jwks_document, jwks_expires_at} <-
             load_jwks(configuration.jwks_uri, ref) do
        {:ok,
         %{
           discovery_document: discovery_document,
           jwks_document: jwks_document,
           discovery_expires_at: discovery_expires_at,
           jwks_expires_at: jwks_expires_at,
           metadata_expires_at: OIDC.metadata_expires_at(discovery_expires_at, jwks_expires_at)
         }}
      end
    end)
  end

  @impl true
  def authorization_uri(
        %Connection{} = connection,
        %Transaction{} = transaction,
        redirect_uri,
        client_secret
      ) do
    url_extension =
      case transaction.login_hint do
        login_hint when is_binary(login_hint) -> [{"login_hint", login_hint}]
        _other -> []
      end

    # Building the redirect URL makes no request today, because the hardened
    # configuration has no pushed authorization endpoint and oidcc short-circuits
    # on that. It goes through the adapter anyway: the alternative is that one
    # struct field three functions away is what keeps this off raw httpc, which
    # follows redirects and has no address pinning or body cap.
    with_adapter(fn ref ->
      with {:ok, client_context} <- client_context(connection, client_secret),
           {:ok, uri} <-
             Oidcc.Authorization.create_redirect_url(client_context, %{
               redirect_uri: redirect_uri,
               scopes: ["openid", "email"],
               state: transaction.raw_state,
               nonce: transaction.nonce,
               pkce_verifier: transaction.code_verifier,
               require_pkce: true,
               url_extension: url_extension,
               request_opts: HTTPAdapter.request_opts(ref, @http_timeout)
             }) do
        {:ok, to_string(uri)}
      else
        {:error, %Error{} = error} -> {:error, error}
        {:error, _reason} -> error(:authorization, :authorization_url_failed)
      end
    end)
  end

  @impl true
  def exchange_code(
        %Connection{} = connection,
        %Transaction{} = transaction,
        code,
        redirect_uri,
        client_secret
      ) do
    with_adapter(fn ref ->
      with {:ok, client_context} <- client_context(connection, client_secret),
           {:ok, claims} <-
             retrieve_token(code, client_context, transaction, redirect_uri, ref),
           :ok <- validate_claims(claims, connection) do
        {refreshed_jwks, refreshed_jwks_expires_at} = refreshed_jwks(ref)

        {:ok,
         %{
           issuer: claims["iss"],
           subject: claims["sub"],
           email: optional_binary(claims["email"]),
           email_verified: claims["email_verified"] == true,
           sid: optional_sid(claims["sid"]),
           jwks_document: refreshed_jwks,
           jwks_expires_at: refreshed_jwks_expires_at
         }}
      end
    end)
  end

  @impl true
  def validate_logout_token(connection, logout_token, opts \\ [])

  def validate_logout_token(%Connection{} = connection, logout_token, opts)
      when is_binary(logout_token) do
    with_adapter(fn ref ->
      with {:ok, client_context} <- client_context(connection, connection.client_secret),
           {:ok, claims} <- validate_logout_jwt(logout_token, client_context, ref, opts),
           :ok <- validate_logout_claims(claims, connection) do
        {refreshed_jwks, refreshed_jwks_expires_at} = refreshed_jwks(ref)

        {:ok,
         %{
           issuer: claims["iss"],
           subject: claims["sub"],
           sid: optional_sid(claims["sid"]),
           jwks_document: refreshed_jwks,
           jwks_expires_at: refreshed_jwks_expires_at
         }}
      end
    end)
  end

  defp with_adapter(fun) do
    ref = HTTPAdapter.open()

    try do
      result = fun.(ref)
      HTTPAdapter.reraise_client_exception!(ref)
      result
    after
      HTTPAdapter.close(ref)
    end
  end

  defp load_configuration(issuer, ref) do
    case Oidcc.ProviderConfiguration.load_configuration(issuer, provider_opts(ref)) do
      {:ok, {configuration, _expiry}} ->
        with {:ok, document, expires_at} <- captured_document(ref, :discovery) do
          {:ok, configuration, document, expires_at}
        end

      {:error, reason} ->
        discovery_error(reason)
    end
  rescue
    _exception -> error(:discovery, :invalid_json)
  end

  defp load_jwks(jwks_uri, ref) do
    case Oidcc.ProviderConfiguration.load_jwks(jwks_uri, provider_opts(ref)) do
      {:ok, {jwks, _expiry}} ->
        with {:ok, document, expires_at} <- captured_document(ref, :jwks),
             :ok <- validate_jwks_document(document) do
          {:ok, jwks, document, expires_at}
        end

      {:error, reason} ->
        jwks_error(reason)
    end
  rescue
    _exception -> error(:jwks, :invalid_document)
  end

  defp retrieve_token(code, client_context, transaction, redirect_uri, ref) do
    opts = %{
      redirect_uri: redirect_uri,
      pkce_verifier: transaction.code_verifier,
      require_pkce: true,
      nonce: transaction.nonce,
      trusted_audiences: [],
      validate_azp: :client_id,
      preferred_auth_methods: @preferred_token_auth_methods,
      refresh_jwks: refresh_jwks_fun(client_context, ref),
      request_opts: HTTPAdapter.request_opts(ref, @http_timeout)
    }

    case oidcc_retrieve(code, client_context, opts, ref) do
      {:ok, %Oidcc.Token{id: %Oidcc.Token.Id{claims: claims}}} -> {:ok, claims}
      {:ok, %Oidcc.Token{}} -> error(:token, :id_token_missing)
      {:error, reason} -> token_error(reason, ref)
    end
  end

  defp oidcc_retrieve(code, client_context, opts, ref) do
    Oidcc.Token.retrieve(code, client_context, opts)
  rescue
    exception ->
      :telemetry.execute(
        [:hexpm, :sso, :oidc, :token_validation_exception],
        %{count: 1},
        %{exception: exception.__struct__, phase: token_phase(ref)}
      )

      {:error, :token_validation_exception}
  end

  # The refresh hook is what turns an unknown `kid` into an outbound JWKS
  # fetch, and this endpoint takes unauthenticated input, so the caller decides
  # per request whether that fetch is on the table.
  defp validate_logout_jwt(logout_token, client_context, ref, opts) do
    validate_opts = %{
      signing_algs: allowed_signing_algorithms(client_context.provider_configuration),
      trusted_audiences: []
    }

    validate_opts =
      if Keyword.get(opts, :refresh_jwks, true) do
        Map.put(validate_opts, :refresh_jwks, refresh_jwks_fun(client_context, ref))
      else
        validate_opts
      end

    case oidcc_validate_jwt(logout_token, client_context, validate_opts, ref) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> logout_token_error(reason)
    end
  end

  defp oidcc_validate_jwt(logout_token, client_context, opts, ref) do
    Oidcc.Token.validate_jwt(logout_token, client_context, opts)
  rescue
    exception ->
      :telemetry.execute(
        [:hexpm, :sso, :oidc, :token_validation_exception],
        %{count: 1},
        %{exception: exception.__struct__, phase: token_phase(ref)}
      )

      {:error, :token_validation_exception}
  end

  defp logout_token_error(%Error{} = error), do: {:error, error}
  defp logout_token_error(:token_expired), do: error(:logout_token, :expired)

  defp logout_token_error({:missing_claim, _claim, _claims}),
    do: error(:logout_token, :required_claim_missing)

  defp logout_token_error({:none_alg_used, _claims}),
    do: error(:logout_token, :signature_invalid)

  defp logout_token_error(:no_matching_key), do: error(:logout_token, :signature_invalid)

  defp logout_token_error({:no_matching_key_with_kid, _kid}),
    do: error(:logout_token, :signature_invalid)

  defp logout_token_error(_reason), do: error(:logout_token, :invalid)

  # oidcc retries validation itself once the refreshed keys come back, so the
  # fetch only has to hand the raw document on for persistence.
  defp refresh_jwks_fun(client_context, ref) do
    jwks_uri = client_context.provider_configuration.jwks_uri

    fn _jwks, _kid ->
      case load_jwks(jwks_uri, ref) do
        {:ok, jwks, document, expires_at} ->
          HTTPAdapter.put(ref, :refreshed_jwks, {document, expires_at})
          {:ok, JOSE.JWK.to_record(jwks)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp refreshed_jwks(ref) do
    case HTTPAdapter.get(ref, :refreshed_jwks) do
      {document, expires_at} -> {document, expires_at}
      nil -> {nil, nil}
    end
  end

  defp token_phase(ref) do
    if HTTPAdapter.get(ref, :refreshed_jwks), do: :jwks_refresh, else: :initial
  end

  defp provider_opts(ref) do
    %{request_opts: HTTPAdapter.request_opts(ref, @http_timeout)}
  end

  defp captured_document(ref, stage) do
    case HTTPAdapter.get(ref, :response) do
      %{headers: headers, body: body} ->
        case JSON.decode(body) do
          {:ok, document} when is_map(document) -> {:ok, document, cache_expiry(headers)}
          _other -> error(stage, :invalid_json)
        end

      nil ->
        error(stage, :unavailable)
    end
  end

  defp discovery_error(%Error{} = error), do: {:error, error}
  defp discovery_error({:issuer_mismatch, _issuer}), do: error(:discovery, :issuer_mismatch)
  defp discovery_error({:http_error, _status, _body}), do: error(:discovery, :http_status)
  defp discovery_error(:invalid_content_type), do: error(:discovery, :invalid_content_type)
  defp discovery_error({:missing_config_property, _key}), do: error(:discovery, :invalid_document)

  defp discovery_error({:invalid_config_property, _property}),
    do: error(:discovery, :invalid_document)

  defp discovery_error({:transport, :response_too_large}),
    do: error(:discovery, :response_too_large)

  defp discovery_error(_reason), do: error(:discovery, :unavailable)

  defp jwks_error(%Error{} = error), do: {:error, error}
  defp jwks_error({:http_error, _status, _body}), do: error(:jwks, :http_status)
  defp jwks_error(:invalid_content_type), do: error(:jwks, :invalid_content_type)
  defp jwks_error({:transport, :response_too_large}), do: error(:jwks, :response_too_large)
  defp jwks_error(_reason), do: error(:jwks, :unavailable)

  defp token_error(%Error{} = error, _ref), do: {:error, error}

  defp token_error({:http_error, _status, _body}, _ref),
    do: error(:token, :token_endpoint_rejected_request)

  defp token_error(:invalid_content_type, _ref), do: error(:token, :invalid_content_type)

  # oidcc turns any non-2xx carrying a dpop-nonce header into this rather than
  # an http_error, and retries once. Reaching here means the endpoint refused
  # twice; blaming the ID token would send an administrator to their signing
  # keys for a problem at the token endpoint.
  defp token_error({:use_dpop_nonce, _nonce, _body}, _ref),
    do: error(:token, :token_endpoint_rejected_request)

  defp token_error({:transport, :response_too_large}, _ref),
    do: error(:token, :response_too_large)

  defp token_error({:transport, _reason}, _ref), do: error(:token, :token_endpoint_unavailable)

  defp token_error(_reason, ref) do
    case token_phase(ref) do
      :jwks_refresh -> error(:token, :id_token_invalid_after_jwks_refresh)
      :initial -> error(:token, :id_token_invalid)
    end
  end

  # There is no lower bound on iat. Microsoft Entra stamps the authentication
  # instant rather than the response instant, so a token minted from an existing
  # provider session is legitimately older than the transaction that asked for
  # it. The nonce binds the token to this transaction and exp bounds its life,
  # which is what stops replay.
  defp validate_claims(claims, connection) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    issued_at = claims["iat"]

    cond do
      claims["iss"] != connection.issuer -> error(:claims, :issuer_mismatch)
      not OIDC.valid_subject?(claims["sub"]) -> error(:claims, :subject_invalid)
      not OIDC.valid_provider_email?(claims["email"]) -> error(:claims, :provider_email_invalid)
      not is_integer(issued_at) -> error(:claims, :issued_at_invalid)
      issued_at > now + @clock_skew_seconds -> error(:claims, :issued_at_in_future)
      true -> :ok
    end
  end

  # The signature, `iss`, `aud`, `exp`, and required-claims checks ran in
  # oidcc, and requiring `sub` there is deliberate: a sid-only logout token is
  # rejected, which sso.md records as a limitation. What oidcc has no notion of
  # is checked here: the logout `events` member, the spec's prohibition on
  # `nonce`, and a freshness window on `iat`, since a logout token is a
  # one-shot signal rather than a credential with its own lifetime.
  defp validate_logout_claims(claims, connection) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    issued_at = claims["iat"]

    cond do
      claims["iss"] != connection.issuer -> error(:logout_token, :issuer_mismatch)
      not OIDC.valid_subject?(claims["sub"]) -> error(:logout_token, :subject_invalid)
      not logout_event?(claims["events"]) -> error(:logout_token, :events_invalid)
      is_map_key(claims, "nonce") -> error(:logout_token, :nonce_present)
      not valid_jti?(claims["jti"]) -> error(:logout_token, :jti_missing)
      not valid_logout_sid?(claims["sid"]) -> error(:logout_token, :sid_invalid)
      not is_integer(issued_at) -> error(:logout_token, :issued_at_invalid)
      issued_at > now + @clock_skew_seconds -> error(:logout_token, :issued_at_in_future)
      issued_at < now - @logout_token_max_age_seconds -> error(:logout_token, :issued_at_too_old)
      true -> :ok
    end
  end

  defp logout_event?(%{@logout_event => event}) when is_map(event), do: true
  defp logout_event?(_events), do: false

  defp valid_jti?(jti), do: is_binary(jti) and jti != ""

  # A sid the sessions cannot carry must fail the logout rather than silently
  # widen it to everything the identity holds.
  defp valid_logout_sid?(nil), do: true

  defp valid_logout_sid?(sid),
    do: is_binary(sid) and sid != "" and byte_size(sid) <= @sid_max_bytes

  defp client_context(connection, client_secret) do
    with {:ok, _uri} <- Issuer.validate_syntax(connection.issuer),
         {:ok, configuration} <-
           decode_configuration(connection.discovery_document, connection.issuer),
         :ok <- validate_configuration(configuration),
         {:ok, jwks} <- decode_jwks(connection.jwks_document) do
      {:ok,
       Oidcc.ClientContext.from_manual(
         harden_configuration(configuration),
         jwks,
         connection.client_id,
         client_secret
       )}
    end
  end

  defp decode_configuration(document, expected_issuer) do
    case Oidcc.ProviderConfiguration.decode_configuration(document) do
      {:ok, %{issuer: ^expected_issuer} = configuration} -> {:ok, configuration}
      {:ok, _configuration} -> error(:discovery, :issuer_mismatch)
      {:error, _reason} -> error(:discovery, :invalid_document)
    end
  rescue
    _exception -> error(:discovery, :invalid_document)
  end

  defp validate_configuration(configuration) do
    signing_algorithms = allowed_signing_algorithms(configuration)

    token_auth_method =
      select_token_auth_method(configuration.token_endpoint_auth_methods_supported)

    cond do
      not is_binary(configuration.authorization_endpoint) ->
        error(:discovery, :authorization_endpoint_missing)

      not is_binary(configuration.token_endpoint) ->
        error(:discovery, :token_endpoint_missing)

      not is_binary(configuration.jwks_uri) ->
        error(:discovery, :jwks_uri_missing)

      configuration.require_pushed_authorization_requests ->
        error(:discovery, :pushed_authorization_requests_unsupported)

      configuration.require_signed_request_object ->
        error(:discovery, :request_objects_unsupported)

      "code" not in configuration.response_types_supported ->
        error(:discovery, :authorization_code_flow_unsupported)

      "authorization_code" not in configuration.grant_types_supported ->
        error(:discovery, :authorization_code_grant_unsupported)

      not pkce_s256_permitted?(configuration.code_challenge_methods_supported) ->
        error(:discovery, :pkce_s256_unsupported)

      signing_algorithms == [] ->
        error(:discovery, :signing_algorithm_unsupported)

      is_nil(token_auth_method) ->
        error(:discovery, :client_secret_auth_unsupported)

      true ->
        :ok
    end
  end

  # Advertising code_challenge_methods_supported is optional, and Microsoft
  # Entra omits it while accepting S256 anyway. Silence means unstated, so only a
  # present list that leaves S256 out is a refusal. An empty list is present: it
  # says the provider supports no methods at all. Hexpm always sends an S256
  # challenge either way, since the hardened configuration asserts it, but a
  # provider that ignores the challenge offers no protection and nothing here can
  # tell that it did.
  defp pkce_s256_permitted?(:undefined), do: true
  defp pkce_s256_permitted?(methods), do: "S256" in List.wrap(methods)

  defp harden_configuration(configuration) do
    %{
      configuration
      | id_token_signing_alg_values_supported: allowed_signing_algorithms(configuration),
        code_challenge_methods_supported: ["S256"],
        pushed_authorization_request_endpoint: :undefined,
        require_pushed_authorization_requests: false,
        request_parameter_supported: false,
        require_signed_request_object: false,
        request_object_signing_alg_values_supported: :undefined,
        request_object_encryption_alg_values_supported: :undefined,
        request_object_encryption_enc_values_supported: :undefined,
        # Hexpm does not accept an encrypted identity token, and saying so keeps
        # oidcc off the branch that returns the claims of a decrypted token
        # without a signature check.
        id_token_encryption_alg_values_supported: :undefined,
        id_token_encryption_enc_values_supported: :undefined
    }
  end

  defp allowed_signing_algorithms(configuration) do
    Enum.filter(
      List.wrap(configuration.id_token_signing_alg_values_supported),
      &(&1 in @allowed_signing_algorithms)
    )
  end

  defp select_token_auth_method(methods) do
    Enum.find(@allowed_token_auth_methods, &(&1 in List.wrap(methods)))
  end

  defp validate_jwks_document(%{"keys" => keys}) when is_list(keys) and keys != [], do: :ok
  defp validate_jwks_document(_document), do: error(:jwks, :invalid_document)

  defp decode_jwks(%{"keys" => keys} = document) when is_list(keys) and keys != [] do
    {:ok, JOSE.JWK.from_map(document)}
  rescue
    _exception -> error(:jwks, :invalid_document)
  end

  defp decode_jwks(_document), do: error(:jwks, :invalid_document)

  defp cache_expiry(headers) do
    cache_control =
      Enum.find_value(headers, fn {name, value} ->
        if String.downcase(to_string(name)) == "cache-control", do: to_string(value)
      end)

    freshness_lifetime =
      cond do
        no_cache?(cache_control) -> 0
        is_binary(cache_control) -> parse_max_age(cache_control) || @fallback_cache_seconds
        true -> @fallback_cache_seconds
      end

    age =
      Enum.find_value(headers, fn {name, value} ->
        if String.downcase(to_string(name)) == "age", do: parse_age(to_string(value))
      end) || 0

    max_age =
      freshness_lifetime
      |> Kernel.-(age)
      |> max(0)
      |> min(24 * 60 * 60)

    DateTime.add(DateTime.utc_now(), max_age, :second)
  end

  defp no_cache?(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.split(",")
    |> Enum.any?(&(String.trim(&1) in ["no-cache", "no-store"]))
  end

  defp no_cache?(_value), do: false

  defp parse_max_age(value) do
    value
    |> String.downcase()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(fn directive ->
      case String.split(directive, "=", parts: 2) do
        ["max-age", value] ->
          case Integer.parse(value) do
            {seconds, ""} when seconds >= 0 -> seconds
            _other -> nil
          end

        _other ->
          nil
      end
    end)
  end

  defp parse_age(value) do
    case Integer.parse(String.trim(value)) do
      {age, ""} when age >= 0 -> age
      _other -> nil
    end
  end

  defp optional_binary(value) when is_binary(value), do: value
  defp optional_binary(_value), do: nil

  # At authentication an unusable sid is dropped rather than failing the login;
  # the session then reads as coming from an unknown provider session, which
  # any logout for the identity revokes. Logout tokens reject unusable sids in
  # `valid_logout_sid?/1` instead, so this clause never widens one.
  defp optional_sid(sid) when is_binary(sid) and sid != "" and byte_size(sid) <= @sid_max_bytes,
    do: sid

  defp optional_sid(_sid), do: nil

  defp error(stage, code), do: {:error, %Error{stage: stage, code: code}}
end
