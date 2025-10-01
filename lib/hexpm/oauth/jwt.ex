defmodule Hexpm.OAuth.JWT do
  @moduledoc """
  JWT token generation and validation for OAuth tokens.
  """

  use Joken.Config

  @impl true
  def token_config do
    default_claims(
      iss: "hexpm",
      aud: "hexpm:api",
      default_exp: 30 * 60
    )
  end

  @doc """
  Generates a JWT access token for a subject (user or organization) with the given scopes.
  """
  def generate_access_token(subject_name, subject_type, scopes, opts \\ []) do
    jti = generate_jti()
    now = unix_now()

    extra_claims = %{
      "sub" => "#{subject_type}:#{subject_name}",
      "jti" => jti,
      "iat" => now,
      "nbf" => now - 30,
      "scope" => Enum.join(scopes, " "),
      "parent_jti" => Keyword.get(opts, :parent_jti)
    }

    expires_in = Keyword.get(opts, :expires_in, 30 * 60)

    extra_claims =
      if expires_in do
        Map.put(extra_claims, "exp", unix_now() + expires_in)
      else
        extra_claims
      end

    signer = get_signer()

    case generate_and_sign(extra_claims, signer) do
      {:ok, token, _claims} -> {:ok, token, jti}
      error -> error
    end
  end

  @doc """
  Generates a JWT refresh token for a subject (user or organization).
  Expiration time should be provided via opts[:expires_in], defaults to 30 days.
  """
  def generate_refresh_token(subject_name, subject_type, scopes, opts \\ []) do
    jti = generate_jti()
    now = unix_now()

    expires_in = Keyword.get(opts, :expires_in, 30 * 24 * 60 * 60)

    extra_claims = %{
      "sub" => "#{subject_type}:#{subject_name}",
      "jti" => jti,
      "iat" => now,
      "nbf" => now - 30,
      "scope" => Enum.join(scopes, " "),
      "exp" => now + expires_in
    }

    signer = get_signer()

    case generate_and_sign(extra_claims, signer) do
      {:ok, token, _claims} -> {:ok, token, jti}
      error -> error
    end
  end

  @doc """
  Validates and decodes a JWT token.
  Returns {:ok, claims} if valid, {:error, reason} otherwise.
  """
  def verify_and_decode(token) do
    signer = get_signer()
    verify_and_validate(token, signer)
  end

  @doc """
  Extracts the JTI (JWT ID) from a token without full validation.
  Useful for revocation checks.
  """
  def extract_jti(token) do
    case peek_claims(token) do
      {:ok, %{"jti" => jti}} -> {:ok, jti}
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Extracts claims without signature verification.
  Use only when you need to check claims before database lookup.
  """
  def peek_claims(token) do
    case Joken.peek_claims(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp generate_jti do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp get_signer do
    key = Application.get_env(:hexpm, :jwt_signing_key)
    Joken.Signer.create("RS256", %{"pem" => key})
  end

  defp unix_now do
    System.system_time(:second)
  end
end
