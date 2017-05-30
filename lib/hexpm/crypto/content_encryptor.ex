defmodule Hexpm.Crypto.ContentEncryptor do
  alias Hexpm.Crypto
  alias __MODULE__

  @type t :: %ContentEncryptor{
    module: module,
    params: any
  }

  defstruct [
    module: nil,
    params: nil
  ]

  @callback init(protected :: map, options :: Keyword.t) ::
            {:ok, any} | {:error, String.t}

  @callback encrypt(params :: any, key :: binary, iv :: binary, {aad :: binary, plain_text :: binary}) ::
            {binary, binary}

  @callback decrypt(params :: any, key :: binary, iv :: binary, {aad :: binary, cipher_text :: binary, cipher_tag :: binary}) ::
            {:ok, binary} | :error

  @callback generate_key(params :: any) ::
            binary

  @callback generate_iv(params :: any) ::
            binary

  @callback key_length(params :: any) ::
            non_neg_integer

  def init(protected = %{enc: enc}, opts) do
    case content_encryptor_module(enc) do
      :error ->
        {:error, "Unrecognized ContentEncryptor algorithm: #{inspect enc}"}
      module ->
        case module.init(protected, opts) do
          {:ok, params} ->
            content_encryptor = %ContentEncryptor{module: module, params: params}
            {:ok, content_encryptor}
          content_encryptor_error ->
            content_encryptor_error
        end
    end
  end

  def encrypt(%ContentEncryptor{module: module, params: params}, key, iv, {aad, plain_text}) do
    module.encrypt(params, key, iv, {aad, plain_text})
  end

  def decrypt(%ContentEncryptor{module: module, params: params}, key, iv, {aad, cipher_text, cipher_tag}) do
    module.decrypt(params, key, iv, {aad, cipher_text, cipher_tag})
  end

  def generate_key(%ContentEncryptor{module: module, params: params}) do
    module.generate_key(params)
  end

  def generate_iv(%ContentEncryptor{module: module, params: params}) do
    module.generate_iv(params)
  end

  def key_length(%ContentEncryptor{module: module, params: params}) do
    module.key_length(params)
  end

  defp content_encryptor_module("A128CBC-HS256"), do: Crypto.AES_CBC_HMAC_SHA2
  defp content_encryptor_module("A192CBC-HS384"), do: Crypto.AES_CBC_HMAC_SHA2
  defp content_encryptor_module("A256CBC-HS512"), do: Crypto.AES_CBC_HMAC_SHA2
  defp content_encryptor_module("A128GCM"), do: Crypto.AES_GCM
  defp content_encryptor_module("A192GCM"), do: Crypto.AES_GCM
  defp content_encryptor_module("A256GCM"), do: Crypto.AES_GCM
  defp content_encryptor_module(_), do: :error
end
