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

  Rejects `none` and symmetric algorithms, validates `nbf`/`exp`/`iat`, and
  requires `aud` to equal `#{@audience}`.
  """
  def verify(token, issuer) when is_binary(token) and is_binary(issuer) do
    with {:ok, header} <- peek_header(token),
         :ok <- validate_alg(header),
         {:ok, jwks} <- get_jwks(issuer),
         {:ok, claims} <- verify_signature(token, jwks, issuer),
         :ok <- validate_claims(claims, issuer) do
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

  defp verify_signature(token, keys, issuer) when is_list(keys) do
    case verify_with_keys(token, keys) do
      {:ok, claims} ->
        {:ok, claims}

      {:error, :signature_invalid} ->
        refresh_and_verify(token, issuer)
    end
  end

  defp verify_with_keys(token, keys) do
    Enum.find_value(keys, {:error, :signature_invalid}, fn key ->
      try do
        case JOSE.JWT.verify_strict(key, @allowed_algs, token) do
          {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
          _ -> nil
        end
      rescue
        _ -> nil
      end
    end)
  end

  defp refresh_and_verify(token, issuer) do
    with :ok <- refresh_allowed?(issuer),
         {:ok, keys} <- fetch_and_cache_jwks(issuer) do
      verify_with_keys(token, keys)
    else
      :refresh_cooldown -> {:error, :signature_invalid}
      _ -> {:error, :signature_invalid}
    end
  end

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

  defp validate_claims(claims, issuer) do
    now = System.system_time(:second)

    cond do
      claims["iss"] != issuer ->
        {:error, :issuer_mismatch}

      not audience_matches?(claims["aud"]) ->
        {:error, :audience_mismatch}

      not is_integer(claims["exp"]) or claims["exp"] < now - @clock_skew_seconds ->
        {:error, :token_expired}

      is_integer(claims["nbf"]) and claims["nbf"] > now + @clock_skew_seconds ->
        {:error, :token_not_yet_valid}

      is_integer(claims["iat"]) and claims["iat"] > now + @clock_skew_seconds ->
        {:error, :issued_at_in_future}

      not is_binary(claims["jti"]) or claims["jti"] == "" ->
        {:error, :jti_missing}

      true ->
        :ok
    end
  end

  defp audience_matches?(aud) when is_binary(aud), do: aud == @audience
  defp audience_matches?(aud) when is_list(aud), do: @audience in aud
  defp audience_matches?(_), do: false

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
    decoded =
      Enum.flat_map(keys, fn key ->
        try do
          [JOSE.JWK.from_map(key)]
        rescue
          _ -> []
        end
      end)

    if decoded == [], do: {:error, :invalid_jwks}, else: {:ok, decoded}
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
