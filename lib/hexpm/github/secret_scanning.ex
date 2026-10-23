defmodule Hexpm.GitHub.SecretScanning do
  @moduledoc """
  Handles GitHub Secret Scanning partner integration.

  Verifies ECDSA-P256-SHA256 signatures on inbound payloads from GitHub
  using GitHub's published public keys, then revokes any matched API keys
  and notifies the affected users.
  """

  require Logger

  alias Hexpm.Accounts.{Auth, Keys}

  @public_keys_url "https://api.github.com/meta/public_keys/secret_scanning"
  @refetch_interval 60
  # prime256v1 / P-256 OID
  @p256_oid {1, 2, 840, 10045, 3, 1, 7}

  @doc """
  Verifies the GitHub ECDSA-P256-SHA256 signature on a raw request body.

  Returns `true` if the signature is valid, `false` otherwise.
  """
  @spec verify_signature(binary(), String.t(), String.t()) :: boolean()
  def verify_signature(raw_body, key_id, signature_b64) do
    case attempt_verify(raw_body, key_id, signature_b64, fetch_public_keys_cached()) do
      {:ok, valid} ->
        valid

      {:error, :key_not_found} ->
        Logger.info("GitHub secret scanning: unknown key_id #{inspect(key_id)}")

        case attempt_verify(raw_body, key_id, signature_b64, refetch_public_keys()) do
          {:ok, valid} ->
            valid

          {:error, reason} ->
            Logger.warning(
              "GitHub secret scanning signature verification failed after key refresh: #{inspect(reason)}"
            )

            false
        end

      {:error, reason} ->
        Logger.warning("GitHub secret scanning signature verification failed: #{inspect(reason)}")
        false
    end
  end

  defp attempt_verify(raw_body, key_id, signature_b64, keys_result) do
    with {:ok, keys} <- keys_result,
         {:ok, pem} <- find_key(keys, key_id),
         {:ok, sig_der} <- decode_signature(signature_b64),
         {:ok, ec_key} <- decode_pem_public_key(pem) do
      {:ok, :public_key.verify(raw_body, :sha256, sig_der, ec_key)}
    end
  end

  defp decode_signature(b64) do
    case Base.decode64(b64) do
      {:ok, sig} -> {:ok, sig}
      :error -> {:error, :invalid_base64}
    end
  end

  @doc false
  @spec fetch_public_keys() :: {:ok, list(map())} | {:error, term()}
  def fetch_public_keys() do
    http = Hexpm.HTTP.impl()

    case http.get(@public_keys_url, [{"accept", "application/json"}]) do
      {:ok, 200, _headers, %{"public_keys" => keys}} ->
        {:ok, keys}

      {:ok, status, _headers, body} ->
        Logger.warning("GitHub public keys fetch returned #{status}: #{inspect(body)}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.warning("GitHub public keys fetch failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  @spec process_alerts(list(map())) :: list(map())
  def process_alerts(alerts) do
    Enum.map(alerts, fn alert ->
      token = Map.get(alert, "token", "")
      %{"token_raw" => token, "token_type" => "hexpm_api_token", "label" => label(alert, token)}
    end)
  end

  # A key that was revoked before the alert is still a real secret, so only a
  # token that matches no key at all is a false positive.
  defp label(alert, token) do
    case Keys.revoke_leaked(secret_first(token), Map.get(alert, "url")) do
      {:ok, :not_found} -> "false_positive"
      {:ok, _revoked} -> "true_positive"
    end
  end

  defp secret_first(token) do
    raw = Auth.strip_token_prefix(token)
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), _rest::binary>> =
      :crypto.mac(:hmac, :sha256, app_secret, raw)
      |> Base.encode16(case: :lower)

    first
  end

  defp find_key(keys, key_id) do
    case Enum.find(keys, &(&1["key_identifier"] == key_id)) do
      nil -> {:error, :key_not_found}
      %{"key" => pem} -> {:ok, pem}
    end
  end

  defp decode_pem_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [{:SubjectPublicKeyInfo, _der, :not_encrypted} = entry] ->
        case :public_key.pem_entry_decode(entry) do
          {{:ECPoint, _}, {:namedCurve, @p256_oid}} = ec_key -> {:ok, ec_key}
          _ -> {:error, :not_p256}
        end

      _ ->
        {:error, :invalid_pem}
    end
  end

  defp fetch_public_keys_cached() do
    ttl = Application.get_env(:hexpm, :github_key_cache_ttl, 300)
    Hexpm.Cache.fetch(:github_secret_scanning_keys, &fetch_public_keys/0, ttl)
  end

  # GitHub signs with a key we haven't fetched yet when it rotates them, but
  # anyone can send an unknown key id, so it refetches at most once a minute.
  defp refetch_public_keys() do
    Hexpm.Cache.refresh(:github_secret_scanning_keys, &fetch_public_keys/0, @refetch_interval)
  end

  @doc false
  def generate_test_keypair() do
    ec_priv_key = :public_key.generate_key({:namedCurve, @p256_oid})
    {:ECPrivateKey, _, _priv, ec_params, pub_point, _} = ec_priv_key
    ec_pub_key = {{:ECPoint, pub_point}, ec_params}

    pem_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, ec_pub_key)
    pem = :public_key.pem_encode([pem_entry])

    {pem, ec_priv_key}
  end

  @doc false
  def sign_payload(payload, ec_private_key) do
    sig_der = :public_key.sign(payload, :sha256, ec_private_key)
    Base.encode64(sig_der)
  end
end
