defmodule Hexpm.Crypto.AES_GCM do
  alias Hexpm.Crypto.ContentEncryptor

  @behaviour ContentEncryptor

  @moduledoc ~S"""
  Content Encryption with AES GCM

  See: https://tools.ietf.org/html/rfc7518#section-5.3
  See: http://csrc.nist.gov/publications/nistpubs/800-38D/SP-800-38D.pdf
  """

  @spec content_encrypt({binary, binary}, <<_::16>> | <<_::24>> | <<_::32>>, <<_::12>>) :: {binary, <<_::16>>}
  def content_encrypt({aad, plain_text}, key, iv)
  when is_binary(aad) and
       is_binary(plain_text) and
       bit_size(key) in [128, 192, 256] and
       bit_size(iv) === 96 do
    :crypto.block_encrypt(:aes_gcm, key, iv, {aad, plain_text})
  end

  @spec content_decrypt({binary, binary, <<_::16>>}, <<_::16>> | <<_::24>> | <<_::32>>, <<_::12>>) :: {:ok, binary} | :error
  def content_decrypt({aad, cipher_text, cipher_tag}, key, iv)
  when is_binary(aad) and
       is_binary(cipher_text) and
       bit_size(cipher_tag) === 128 and
       bit_size(key) in [128, 192, 256] and
       bit_size(iv) === 96 do
    case :crypto.block_decrypt(:aes_gcm, key, iv, {aad, cipher_text, cipher_tag}) do
      plain_text when is_binary(plain_text) ->
        {:ok, plain_text}
      _ ->
        :error
    end
  end

  def init(%{enc: enc}, _opts) do
    {:ok, %{key_length: encoding_to_key_length(enc)}}
  end

  def encrypt(%{key_length: key_length}, key, iv, {aad, plain_text})
  when byte_size(key) == key_length do
    content_encrypt({aad, plain_text}, key, iv)
  end

  def decrypt(%{key_length: key_length}, key, iv, {aad, cipher_text, cipher_tag})
  when byte_size(key) == key_length do
    content_decrypt({aad, cipher_text, cipher_tag}, key, iv)
  end

  def generate_key(%{key_length: key_length}) do
    :crypto.strong_rand_bytes(key_length)
  end

  def generate_iv(_params) do
    :crypto.strong_rand_bytes(12)
  end

  def key_length(%{key_length: key_length}) do
    key_length
  end

  defp encoding_to_key_length("A128GCM"), do: 16
  defp encoding_to_key_length("A192GCM"), do: 24
  defp encoding_to_key_length("A256GCM"), do: 32
end
