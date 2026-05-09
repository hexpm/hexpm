defmodule Hexpm.GitHub.SecretScanning do
  @moduledoc """
  Handles GitHub Secret Scanning partner integration.

  Verifies ECDSA-P256-SHA256 signatures on inbound payloads from GitHub
  using GitHub's published public keys, then revokes any matched API keys
  and notifies the affected users.
  """

  require Logger

  alias Hexpm.Accounts.{Key, Keys}

  @public_keys_url "https://api.github.com/meta/public_keys/secret_scanning"
  # prime256v1 / P-256 OID
  @p256_oid {1, 2, 840, 10045, 3, 1, 7}
  @token_prefix Key.token_prefix()

  @doc """
  Verifies the GitHub ECDSA-P256-SHA256 signature on a raw request body.

  Returns `true` if the signature is valid, `false` otherwise.
  """
  @spec verify_signature(binary(), String.t(), String.t()) :: boolean()
  def verify_signature(raw_body, key_id, signature_b64) do
    with {:ok, keys} <- fetch_public_keys_cached(),
         {:ok, pem} <- find_key(keys, key_id),
         {:ok, sig_der} <- Base.decode64(signature_b64),
         {:ok, ec_key} <- decode_pem_public_key(pem) do
      :public_key.verify(raw_body, :sha256, sig_der, ec_key)
    else
      err ->
        Logger.warning("GitHub secret scanning signature verification failed: #{inspect(err)}")
        false
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
      url = Map.get(alert, "url")

      case revoke_token(token) do
        {:ok, key, user} ->
          if user do
            Hexpm.Emails.key_leaked(user, key, url) |> Hexpm.Emails.Mailer.deliver_later()
          end

          %{"token_raw" => token, "token_type" => "hexpm_api_token", "label" => "true_positive"}

        :not_found ->
          %{"token_raw" => token, "token_type" => "hexpm_api_token", "label" => "false_positive"}
      end
    end)
  end

  defp revoke_token(token) do
    raw =
      case token do
        @token_prefix <> body -> body
        other -> other
      end

    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), _rest::binary>> =
      :crypto.mac(:hmac, :sha256, app_secret, raw)
      |> Base.encode16(case: :lower)

    case Keys.get_by_secret_first(first) do
      nil ->
        :not_found

      {key, user} ->
        Keys.revoke_immediately(key)
        {:ok, key, user}
    end
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
    Hexpm.Cache.fetch(Hexpm.Cache, :github_secret_scanning_keys, &fetch_public_keys/0, ttl: ttl)
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
