defmodule Hexpm.Crypto.PBES2_HMAC_SHA2 do
  alias Hexpm.Crypto.ContentEncryptor
  alias Hexpm.Crypto.KeyManager
  alias Hexpm.Crypto.PKCS5

  @behaviour KeyManager

  @moduledoc ~S"""
  Direct Key Derivation with PBES2 and HMAC-SHA-2.

  See: https://tools.ietf.org/html/rfc7518#section-4.8
  See: https://tools.ietf.org/html/rfc2898#section-6.2
  """

  @spec derive_key(String.t, binary, pos_integer, non_neg_integer, :sha256 | :sha384 | :sha512) :: binary
  def derive_key(password, salt_input, iterations, derived_key_length, hash)
  when is_binary(password) and
       is_binary(salt_input) and
       is_integer(iterations) and iterations >= 1 and
       is_integer(derived_key_length) and derived_key_length >= 0 and
       hash in [:sha256, :sha384, :sha512] do
    salt = wrap_salt_input(salt_input, hash)
    derived_key = PKCS5.pbkdf2(password, salt, iterations, derived_key_length, hash)
    derived_key
  end

  def init(%{alg: alg} = protected, opts) do
    hash = algorithm_to_hash(alg)
    case fetch_password(opts) do
      {:ok, password} ->
        case fetch_p2c(protected) do
          {:ok, _iteration} ->
            protected
            |> fetch_p2s()
            |> handle_p2s(hash, password)
          error ->
            error
        end
      error ->
        error
    end
  end

  def encrypt(%{password: password, hash: hash}, %{p2c: iterations, p2s: salt} = protected, content_encryptor) do
    derived_key_length = ContentEncryptor.key_length(content_encryptor)
    key = derive_key(password, salt, iterations, derived_key_length, hash)
    encrypted_key = ""
    {:ok, protected, key, encrypted_key}
  end

  def decrypt(%{password: password, hash: hash}, %{p2c: iterations, p2s: salt}, "", content_encryptor) do
    derived_key_length = ContentEncryptor.key_length(content_encryptor)
    key = derive_key(password, salt, iterations, derived_key_length, hash)
    {:ok, key}
  end
  def decrypt(_, _, _, _), do: :error

  defp handle_p2s({:ok, _salt}, hash, passwd), do: {:ok, %{hash: hash, password: passwd}}
  defp handle_p2s(error, _, _), do: error

  defp fetch_password(opts) do
    case Keyword.fetch(opts, :password) do
      {:ok, password} when is_binary(password) -> {:ok, password}
      _ -> {:error, "option :password (PBKDF2 password) must be a binary"}
    end
  end

  defp fetch_p2c(opts) do
    case Map.fetch(opts, :p2c) do
      {:ok, p2c} when is_integer(p2c) and p2c >= 1 -> {:ok, p2c}
      _ -> {:error, "protected :p2c (PBKDF2 iterations) must be a positive integer"}
    end
  end

  defp fetch_p2s(opts) do
    case Map.fetch(opts, :p2s) do
      {:ok, p2s} when is_binary(p2s) -> {:ok, p2s}
      _ -> {:error, "protected :p2s (PBKDF2 salt) must be a binary"}
    end
  end

  defp wrap_salt_input(salt_input, :sha256),
    do: <<"PBES2-HS256", 0, salt_input::binary>>
  defp wrap_salt_input(salt_input, :sha384),
    do: <<"PBES2-HS384", 0, salt_input::binary>>
  defp wrap_salt_input(salt_input, :sha512),
    do: <<"PBES2-HS512", 0, salt_input::binary>>

  defp algorithm_to_hash("PBES2-HS256"), do: :sha256
  defp algorithm_to_hash("PBES2-HS384"), do: :sha384
  defp algorithm_to_hash("PBES2-HS512"), do: :sha512
end
