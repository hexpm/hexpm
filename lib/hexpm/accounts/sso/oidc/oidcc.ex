defmodule Hexpm.Accounts.SSO.OIDC.Oidcc do
  @behaviour Hexpm.Accounts.SSO.OIDC

  alias Hexpm.Accounts.SSO.{Connection, Error, SafeURL, Transaction}

  @allowed_signing_algorithms ~w(RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 EdDSA)
  @allowed_token_auth_methods ~w(client_secret_basic client_secret_post)
  @fallback_cache_seconds 3_600
  @http_timeout 5_000
  @max_response_bytes 1_000_000
  @clock_skew_seconds 60

  @impl true
  def discover(issuer) do
    discovery_url = String.trim_trailing(issuer, "/") <> "/.well-known/openid-configuration"

    with {:ok, _uri} <- SafeURL.validate(issuer),
         {:ok, discovery_document, discovery_expiry} <- fetch_json(discovery_url, :discovery),
         {:ok, configuration} <- decode_configuration(discovery_document, issuer),
         :ok <- validate_configuration(configuration),
         {:ok, _uri} <- SafeURL.validate(configuration.authorization_endpoint),
         {:ok, _uri} <- SafeURL.validate(configuration.token_endpoint),
         {:ok, _uri} <- SafeURL.validate(configuration.jwks_uri),
         {:ok, jwks_document, jwks_expiry} <- fetch_json(configuration.jwks_uri, :jwks),
         {:ok, _jwks} <- decode_jwks(jwks_document) do
      {:ok,
       %{
         discovery_document: discovery_document,
         jwks_document: jwks_document,
         discovery_expires_at: discovery_expiry,
         jwks_expires_at: jwks_expiry,
         metadata_expires_at: earliest(discovery_expiry, jwks_expiry)
       }}
    end
  end

  @impl true
  def authorization_uri(
        %Connection{} = connection,
        %Transaction{} = transaction,
        redirect_uri,
        client_secret
      ) do
    with {:ok, client_context} <- client_context(connection, client_secret),
         {:ok, uri} <-
           Oidcc.Authorization.create_redirect_url(client_context, %{
             redirect_uri: redirect_uri,
             scopes: ["openid", "email"],
             state: transaction.raw_state,
             nonce: transaction.nonce,
             pkce_verifier: transaction.code_verifier,
             require_pkce: true
           }) do
      {:ok, to_string(uri)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, _reason} -> error(:authorization, :authorization_url_failed)
    end
  end

  @impl true
  def exchange_code(
        %Connection{} = connection,
        %Transaction{} = transaction,
        code,
        redirect_uri,
        client_secret
      ) do
    with {:ok, client_context} <- client_context(connection, client_secret),
         {:ok, token_response} <-
           request_token(client_context.provider_configuration, connection, code, redirect_uri,
             code_verifier: transaction.code_verifier,
             client_secret: client_secret
           ),
         {:ok, id_token} <- fetch_id_token(token_response),
         {:ok, claims, refreshed_jwks, refreshed_jwks_expiry} <-
           validate_id_token(id_token, client_context, transaction, connection),
         :ok <- validate_claims(claims, transaction, connection) do
      {:ok,
       %{
         issuer: claims["iss"],
         subject: claims["sub"],
         email: optional_binary(claims["email"]),
         jwks_document: refreshed_jwks,
         jwks_expires_at: refreshed_jwks_expiry
       }}
    end
  end

  defp request_token(configuration, connection, code, redirect_uri, opts) do
    method = select_token_auth_method(configuration.token_endpoint_auth_methods_supported)
    client_secret = Keyword.fetch!(opts, :client_secret)

    body = %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri,
      "code_verifier" => Keyword.fetch!(opts, :code_verifier)
    }

    {headers, body} = token_request_auth(method, connection, client_secret, body)

    with {:ok, uri, addresses} <- SafeURL.resolve(configuration.token_endpoint),
         {:ok, 200, response_headers, response_body} <-
           Hexpm.HTTP.impl().post(configuration.token_endpoint, headers, body,
             decode_body: false,
             connect_address: List.first(addresses),
             connect_hostname: uri.host,
             max_body_bytes: @max_response_bytes,
             receive_timeout: @http_timeout,
             request_timeout: @http_timeout
           ),
         {:ok, response} <- decode_json_response(response_headers, response_body, :token) do
      {:ok, response}
    else
      {:ok, _status, _headers, _body} -> error(:token, :token_endpoint_rejected_request)
      {:error, :response_too_large} -> error(:token, :response_too_large)
      {:error, %Error{} = error} -> {:error, error}
      {:error, _reason} -> error(:token, :token_endpoint_unavailable)
    end
  end

  defp token_request_auth("client_secret_basic", connection, client_secret, body) do
    credentials =
      URI.encode_www_form(connection.client_id) <>
        ":" <> URI.encode_www_form(client_secret)

    headers = [
      {"accept", "application/json"},
      {"authorization", "Basic " <> Base.encode64(credentials)},
      {"content-type", "application/x-www-form-urlencoded"}
    ]

    {headers, body}
  end

  defp token_request_auth("client_secret_post", connection, client_secret, body) do
    headers = [
      {"accept", "application/json"},
      {"content-type", "application/x-www-form-urlencoded"}
    ]

    {headers,
     Map.merge(body, %{"client_id" => connection.client_id, "client_secret" => client_secret})}
  end

  defp validate_id_token(id_token, client_context, transaction, connection) do
    opts = %{nonce: transaction.nonce, trusted_audiences: [], validate_azp: :client_id}

    case oidcc_validate_id_token(id_token, client_context, opts, :initial) do
      {:ok, claims} ->
        {:ok, claims, nil, nil}

      {:error, {:no_matching_key_with_kid, _kid}} ->
        refresh_and_validate_id_token(id_token, client_context, transaction, connection, opts)

      {:error, _reason} ->
        error(:token, :id_token_invalid)
    end
  end

  defp refresh_and_validate_id_token(id_token, client_context, transaction, connection, opts) do
    jwks_uri = client_context.provider_configuration.jwks_uri

    with {:ok, _uri} <- SafeURL.validate(jwks_uri),
         {:ok, jwks_document, expiry} <- fetch_json(jwks_uri, :jwks),
         {:ok, jwks} <- decode_jwks(jwks_document),
         refreshed_context <- %{client_context | jwks: jwks},
         {:ok, claims} <-
           oidcc_validate_id_token(id_token, refreshed_context, opts, :jwks_refresh),
         :ok <- validate_claims(claims, transaction, connection) do
      {:ok, claims, jwks_document, expiry}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, _reason} -> error(:token, :id_token_invalid_after_jwks_refresh)
    end
  end

  defp oidcc_validate_id_token(id_token, client_context, opts, phase) do
    Oidcc.Token.validate_id_token(id_token, client_context, opts)
  rescue
    exception ->
      :telemetry.execute(
        [:hexpm, :sso, :oidc, :token_validation_exception],
        %{count: 1},
        %{exception: exception.__struct__, phase: phase}
      )

      {:error, :token_validation_exception}
  end

  defp validate_claims(claims, transaction, connection) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    transaction_started = DateTime.to_unix(transaction.inserted_at)
    issued_at = claims["iat"]

    cond do
      claims["iss"] != connection.issuer -> error(:claims, :issuer_mismatch)
      not valid_subject?(claims["sub"]) -> error(:claims, :subject_invalid)
      not valid_provider_email?(claims["email"]) -> error(:claims, :provider_email_invalid)
      not is_integer(issued_at) -> error(:claims, :issued_at_invalid)
      issued_at < transaction_started - @clock_skew_seconds -> error(:claims, :issued_at_too_old)
      issued_at > now + @clock_skew_seconds -> error(:claims, :issued_at_in_future)
      true -> :ok
    end
  end

  defp client_context(connection, client_secret) do
    with {:ok, configuration} <-
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

      "S256" not in List.wrap(configuration.code_challenge_methods_supported) ->
        error(:discovery, :pkce_s256_unsupported)

      signing_algorithms == [] ->
        error(:discovery, :signing_algorithm_unsupported)

      is_nil(token_auth_method) ->
        error(:discovery, :client_secret_auth_unsupported)

      true ->
        :ok
    end
  end

  defp harden_configuration(configuration) do
    %{
      configuration
      | id_token_signing_alg_values_supported: allowed_signing_algorithms(configuration),
        pushed_authorization_request_endpoint: :undefined,
        require_pushed_authorization_requests: false,
        request_parameter_supported: false,
        require_signed_request_object: false,
        request_object_signing_alg_values_supported: :undefined,
        request_object_encryption_alg_values_supported: :undefined,
        request_object_encryption_enc_values_supported: :undefined
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

  defp fetch_id_token(%{"id_token" => id_token}) when is_binary(id_token) and id_token != "",
    do: {:ok, id_token}

  defp fetch_id_token(_response), do: error(:token, :id_token_missing)

  defp fetch_json(url, stage) do
    with {:ok, uri, addresses} <- SafeURL.resolve(url),
         {:ok, 200, headers, body} <-
           Hexpm.HTTP.impl().get(url, [{"accept", "application/json"}],
             decode_body: false,
             connect_address: List.first(addresses),
             connect_hostname: uri.host,
             max_body_bytes: @max_response_bytes,
             receive_timeout: @http_timeout,
             request_timeout: @http_timeout
           ),
         {:ok, document} <- decode_json_response(headers, body, stage) do
      {:ok, document, cache_expiry(headers)}
    else
      {:ok, _status, _headers, _body} -> error(stage, :http_status)
      {:error, :response_too_large} -> error(stage, :response_too_large)
      {:error, %Error{} = error} -> {:error, error}
      {:error, _reason} -> error(stage, :unavailable)
    end
  end

  defp decode_json_response(headers, body, stage)
       when is_binary(body) and byte_size(body) <= @max_response_bytes do
    if json_content_type?(headers) do
      case JSON.decode(body) do
        {:ok, document} when is_map(document) -> {:ok, document}
        _other -> error(stage, :invalid_json)
      end
    else
      error(stage, :invalid_content_type)
    end
  end

  defp decode_json_response(_headers, _body, stage), do: error(stage, :response_too_large)

  defp json_content_type?(headers) do
    Enum.any?(headers, fn {name, value} ->
      media_type =
        value
        |> to_string()
        |> String.split(";", parts: 2)
        |> List.first()
        |> String.trim()
        |> String.downcase()

      String.downcase(to_string(name)) == "content-type" and
        (media_type == "application/json" or
           (String.starts_with?(media_type, "application/") and
              String.ends_with?(media_type, "+json")))
    end)
  end

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

  defp earliest(left, right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
  end

  defp optional_binary(value) when is_binary(value), do: value
  defp optional_binary(_value), do: nil

  defp valid_subject?(subject) when is_binary(subject) do
    subject != "" and byte_size(subject) <= 255 and
      subject |> :binary.bin_to_list() |> Enum.all?(&(&1 <= 127))
  end

  defp valid_subject?(_subject), do: false

  defp valid_provider_email?(nil), do: true

  defp valid_provider_email?(email) when is_binary(email) do
    byte_size(email) <= 320 and String.valid?(email)
  end

  defp valid_provider_email?(_email), do: false

  defp error(stage, code), do: {:error, %Error{stage: stage, code: code}}
end
