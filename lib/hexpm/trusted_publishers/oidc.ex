defmodule Hexpm.TrustedPublishers.OIDC do
  @moduledoc """
  OIDC discovery, JWKS caching, and JWT verification for trusted publishers.
  """

  @audience "hexpm"
  @allowed_algs ~w(RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 EdDSA)
  @fallback_cache_seconds 3_600
  @http_timeout 5_000
  @max_response_bytes 1_000_000
  @clock_skew_seconds 60
  @min_refresh_interval_seconds 30

  def audience, do: @audience

  @doc """
  Peeks claims without verifying the signature.
  """
  def peek_claims(token) when is_binary(token) do
    case Joken.peek_claims(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  def peek_claims(_), do: {:error, :invalid_token}

  @doc """
  Verifies an OIDC JWT against the given issuer.

  Signature, `iss`, `aud`, `exp`, and `nbf` validation is delegated to
  `Oidcc.Token.validate_jwt/3`. This module rejects `none` and symmetric
  algorithms before handing the token over, and checks `jti` and an upper bound
  on `iat` afterwards, neither of which the generic JWT validation covers.
  """
  def verify(token, issuer) when is_binary(token) and is_binary(issuer) do
    with {:ok, header} <- peek_header(token),
         :ok <- validate_alg(header),
         {:ok, jwks} <- get_jwks(issuer),
         {:ok, claims} <- validate_jwt(token, jwks, issuer),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    end
  end

  def verify(_, _), do: {:error, :invalid_token}

  defp peek_header(token) do
    case Joken.peek_header(token) do
      {:ok, header} -> {:ok, header}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp validate_alg(%{"alg" => alg}) when alg in @allowed_algs, do: :ok
  defp validate_alg(%{"alg" => "none"}), do: {:error, :algorithm_rejected}

  defp validate_alg(%{"alg" => alg}) when alg in ~w(HS256 HS384 HS512),
    do: {:error, :algorithm_rejected}

  defp validate_alg(_), do: {:error, :algorithm_rejected}

  defp get_jwks(issuer) do
    case :persistent_term.get({__MODULE__, :jwks, issuer}, :miss) do
      {:ok, jwks, expires_at} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, jwks}
        else
          fetch_and_cache_jwks(issuer)
        end

      :miss ->
        fetch_and_cache_jwks(issuer)
    end
  end

  defp fetch_and_cache_jwks(issuer) do
    discovery_url = String.trim_trailing(issuer, "/") <> "/.well-known/openid-configuration"

    with {:ok, discovery, _} <- fetch_json(discovery_url),
         jwks_uri when is_binary(jwks_uri) <- Map.get(discovery, "jwks_uri"),
         {:ok, jwks_document, expires_at} <- fetch_json(jwks_uri),
         {:ok, jwks} <- decode_jwks(jwks_document) do
      put_jwks_cache(issuer, jwks, expires_at)
      {:ok, jwks}
    else
      nil -> {:error, :jwks_uri_missing}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :discovery_failed}
    end
  end

  defp put_jwks_cache(issuer, jwks, expires_at) do
    case :persistent_term.get({__MODULE__, :jwks, issuer}, :miss) do
      {:ok, ^jwks, _expires_at} ->
        :ok

      _ ->
        :persistent_term.put({__MODULE__, :jwks, issuer}, {:ok, jwks, expires_at})
    end

    :persistent_term.put({__MODULE__, :jwks_refreshed_at, issuer}, DateTime.utc_now())
    :ok
  end

  defp validate_jwt(token, jwks, issuer) do
    case oidcc_validate_jwt(token, jwks, issuer) do
      {:ok, claims} ->
        {:ok, claims}

      {:error, error} ->
        if unknown_key?(error) do
          refresh_and_validate_jwt(token, issuer, error)
        else
          {:error, translate_error(error)}
        end
    end
  end

  defp refresh_and_validate_jwt(token, issuer, error) do
    with :ok <- refresh_allowed?(issuer),
         {:ok, jwks} <- fetch_and_cache_jwks(issuer) do
      case oidcc_validate_jwt(token, jwks, issuer) do
        {:ok, claims} -> {:ok, claims}
        {:error, refresh_error} -> {:error, translate_error(refresh_error)}
      end
    else
      :refresh_cooldown -> {:error, translate_error(error)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp oidcc_validate_jwt(token, jwks, issuer) do
    Oidcc.Token.validate_jwt(token, client_context(jwks, issuer), %{
      signing_algs: @allowed_algs,
      trusted_audiences: :any
    })
  rescue
    _exception -> {:error, :signature_invalid}
  end

  # GitHub is not an interactive OpenID provider: its discovery document carries
  # no authorization endpoint, so it cannot be decoded with
  # `Oidcc.ProviderConfiguration.decode_configuration/1`. Only the issuer is read
  # back out during generic JWT validation.
  defp client_context(jwks, issuer) do
    configuration = %Oidcc.ProviderConfiguration{
      issuer: issuer,
      id_token_signing_alg_values_supported: @allowed_algs
    }

    Oidcc.ClientContext.from_manual(configuration, jwks, @audience, :unauthenticated)
  end

  defp unknown_key?(:no_matching_key), do: true
  defp unknown_key?({:no_matching_key_with_kid, _kid}), do: true
  defp unknown_key?(_error), do: false

  defp translate_error(:token_expired), do: :token_expired
  defp translate_error(:token_not_yet_valid), do: :token_not_yet_valid
  defp translate_error(:none_alg_used), do: :algorithm_rejected
  defp translate_error({:none_alg_used, _claims}), do: :algorithm_rejected

  defp translate_error({:missing_claim, claim, _claims}),
    do: translate_missing_claim(missing_claim_name(claim))

  defp translate_error(reason) when reason in [:no_matching_key, :signature_invalid],
    do: :signature_invalid

  defp translate_error({:no_matching_key_with_kid, _kid}), do: :signature_invalid
  defp translate_error(_reason), do: :invalid_token

  defp missing_claim_name({name, _expected}), do: name
  defp missing_claim_name(name), do: name

  defp translate_missing_claim("iss"), do: :issuer_mismatch
  defp translate_missing_claim("aud"), do: :audience_mismatch
  defp translate_missing_claim("exp"), do: :token_expired
  defp translate_missing_claim(_claim), do: :invalid_token

  defp refresh_allowed?(issuer) do
    case :persistent_term.get({__MODULE__, :jwks_refreshed_at, issuer}, nil) do
      nil ->
        :ok

      refreshed_at ->
        if DateTime.diff(DateTime.utc_now(), refreshed_at, :second) >=
             @min_refresh_interval_seconds do
          :ok
        else
          :refresh_cooldown
        end
    end
  end

  defp validate_claims(claims) do
    now = System.system_time(:second)

    cond do
      is_integer(claims["iat"]) and claims["iat"] > now + @clock_skew_seconds ->
        {:error, :issued_at_in_future}

      not is_binary(claims["jti"]) or claims["jti"] == "" ->
        {:error, :jti_missing}

      true ->
        :ok
    end
  end

  defp fetch_json(url) do
    case Hexpm.HTTP.impl().get(url, [{"accept", "application/json"}],
           decode_body: false,
           max_body_bytes: @max_response_bytes,
           receive_timeout: @http_timeout,
           request_timeout: @http_timeout
         ) do
      {:ok, 200, headers, body} when is_binary(body) ->
        case JSON.decode(body) do
          {:ok, document} when is_map(document) ->
            {:ok, document, cache_expiry(headers)}

          _ ->
            {:error, :invalid_json}
        end

      {:ok, _status, _headers, _body} ->
        {:error, :http_status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_jwks(%{"keys" => keys}) when is_list(keys) and keys != [] do
    {:ok, JOSE.JWK.from_map(%{"keys" => keys})}
  end

  defp decode_jwks(_), do: {:error, :invalid_jwks}

  defp cache_expiry(headers) do
    cache_control =
      Enum.find_value(headers, fn {name, value} ->
        if String.downcase(to_string(name)) == "cache-control", do: to_string(value)
      end)

    max_age =
      cond do
        is_binary(cache_control) and String.contains?(String.downcase(cache_control), "no-store") ->
          0

        is_binary(cache_control) ->
          parse_max_age(cache_control) || @fallback_cache_seconds

        true ->
          @fallback_cache_seconds
      end

    DateTime.add(DateTime.utc_now(), max(max_age, 0), :second)
  end

  defp parse_max_age(value) do
    value
    |> String.downcase()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(fn directive ->
      case String.split(directive, "=", parts: 2) do
        ["max-age", seconds] ->
          case Integer.parse(seconds) do
            {n, ""} when n >= 0 -> n
            _ -> nil
          end

        _ ->
          nil
      end
    end)
  end

  @doc false
  def clear_cache do
    for issuer <- Hexpm.TrustedPublishers.Provider.known_issuers() do
      :persistent_term.erase({__MODULE__, :jwks, issuer})
      :persistent_term.erase({__MODULE__, :jwks_refreshed_at, issuer})
    end

    :ok
  end
end
