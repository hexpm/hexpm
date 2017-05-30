defmodule Hexpm.Crypto.KeyManager do
  alias Hexpm.Crypto
  alias Hexpm.Crypto.ContentEncryptor
  alias __MODULE__

  @type t :: %KeyManager{
    module: module,
    params: any
  }

  defstruct [
    module: nil,
    params: nil
  ]

  @callback init(protected :: map, options :: Keyword.t) ::
            {:ok, any} | {:error, String.t}

  @callback encrypt(params :: any, protected :: map, content_encryptor :: ContentEncryptor.t) ::
            {:ok, map, binary, binary} | {:error, String.t}

  @callback decrypt(params :: any, protected :: map, encrypted_key :: binary, content_encryptor :: ContentEncryptor.t) ::
            {:ok, binary} | {:error, String.t}

  def init(%{alg: alg} = protected, opts) do
    case key_manager_module(alg) do
      {:ok, module} ->
        case module.init(protected, opts) do
          {:ok, params} ->
            key_manager = %KeyManager{module: module, params: params}
            fetch_content_encryptor(key_manager, protected, opts)
          key_manager_error ->
            key_manager_error
        end
      error ->
        error
    end
  end

  def encrypt(protected, opts) do
    case init(protected, opts) do
      {:ok, %KeyManager{module: module, params: params}, content_encryptor} ->
        case module.encrypt(params, protected, content_encryptor) do
          {:ok, protected, key, encrypted_key} ->
            {:ok, protected, key, encrypted_key, content_encryptor}
          key_manager_error ->
            key_manager_error
        end
      init_error ->
        init_error
    end
  end

  def decrypt(protected, encrypted_key, opts) do
    case init(protected, opts) do
      {:ok, %KeyManager{module: module, params: params}, content_encryptor} ->
        case module.decrypt(params, protected, encrypted_key, content_encryptor) do
          {:ok, key} ->
            {:ok, key, content_encryptor}
          key_manager_error ->
            key_manager_error
        end
      init_error ->
        init_error
    end
  end

  defp key_manager_module("PBES2-HS256"), do: {:ok, Crypto.PBES2_HMAC_SHA2}
  defp key_manager_module("PBES2-HS384"), do: {:ok, Crypto.PBES2_HMAC_SHA2}
  defp key_manager_module("PBES2-HS512"), do: {:ok, Crypto.PBES2_HMAC_SHA2}
  defp key_manager_module(alg), do: {:error, "Unrecognized KeyManager algorithm: #{inspect alg}"}

  defp fetch_content_encryptor(key_manager, protected, opts) do
    case ContentEncryptor.init(protected, opts) do
      {:ok, content_encryptor} ->
        {:ok, key_manager, content_encryptor}
      error ->
        error
    end
  end
end
