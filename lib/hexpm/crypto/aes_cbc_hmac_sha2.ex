defmodule Hexpm.Crypto.AES_CBC_HMAC_SHA2 do
  alias Hexpm.Crypto.ContentEncryptor

  @behaviour ContentEncryptor

  @moduledoc ~S"""
  Content Encryption with AES_CBC_HMAC_SHA2.

  See: https://tools.ietf.org/html/rfc7518#section-5.2.6
  """

  @spec content_encrypt({binary, binary}, <<_::32>> | <<_::48>> | <<_::64>>, <<_::16>>) :: {binary, <<_::16>> | <<_::24>> | <<_::32>>}
  def content_encrypt({aad, plain_text}, key, iv)
  when is_binary(aad) and
       is_binary(plain_text) and
       bit_size(key) in [256, 384, 512] and
       bit_size(iv) === 128 do
    mac_size = div(byte_size(key), 2)
    enc_size = mac_size
    tag_size = mac_size
    <<mac_key::binary-size(mac_size), enc_key::binary-size(enc_size)>> = key
    cipher_text = aes_cbc_encrypt(enc_key, iv, pkcs7_pad(plain_text))
    aad_length = <<bit_size(aad)::1-unsigned-big-integer-unit(64)>>
    mac_data = aad <> iv <> cipher_text <> aad_length
    <<cipher_tag::binary-size(tag_size), _::binary>> = hmac_sha2(mac_key, mac_data)
    {cipher_text, cipher_tag}
  end

  @spec content_decrypt({binary, binary, <<_::16>> | <<_::24>> | <<_::32>>}, <<_::32>> | <<_::48>> | <<_::64>>, <<_::16>>) :: {:ok, binary} | :error
  def content_decrypt({aad, cipher_text, cipher_tag}, key, iv)
  when is_binary(aad) and
       is_binary(cipher_text) and
       bit_size(cipher_tag) in [128, 192, 256] and
       bit_size(key) in [256, 384, 512] and
       bit_size(iv) === 128 do
    mac_size = div(byte_size(key), 2)
    enc_size = mac_size
    tag_size = mac_size
    <<mac_key::binary-size(mac_size), enc_key::binary-size(enc_size)>> = key
    aad_length = <<bit_size(aad)::1-unsigned-big-integer-unit(64)>>
    mac_data = aad <> iv <> cipher_text <> aad_length
    case hmac_sha2(mac_key, mac_data) do
      <<^cipher_tag::binary-size(tag_size), _::binary>> ->
        case aes_cbc_decrypt(enc_key, iv, cipher_text) do
          plain_text when is_binary(plain_text) ->
            pkcs7_unpad(plain_text)
          _ ->
            :error
        end
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
    :crypto.strong_rand_bytes(16)
  end

  def key_length(%{key_length: key_length}) do
    key_length
  end

  # Support new and old style AES-CBC calls.
  defp aes_cbc_encrypt(key, iv, plain_text) do
    :crypto.block_encrypt(:aes_cbc, key, iv, plain_text)
  rescue
    FunctionClauseError ->
      key
      |> bit_size()
      |> bit_size_to_cipher()
      |> :crypto.block_encrypt(key, iv, plain_text)
  end

  # Support new and old style AES-CBC calls.
  defp aes_cbc_decrypt(key, iv, cipher_text) do
    :crypto.block_decrypt(:aes_cbc, key, iv, cipher_text)
  rescue
    FunctionClauseError ->
      key
      |> bit_size()
      |> bit_size_to_cipher()
      |> :crypto.block_decrypt(key, iv, cipher_text)
  end

  defp hmac_sha2(mac_key, mac_data) when bit_size(mac_key) === 128,
    do: :crypto.hmac(:sha256, mac_key, mac_data)
  defp hmac_sha2(mac_key, mac_data) when bit_size(mac_key) === 192,
    do: :crypto.hmac(:sha384, mac_key, mac_data)
  defp hmac_sha2(mac_key, mac_data) when bit_size(mac_key) === 256,
    do: :crypto.hmac(:sha512, mac_key, mac_data)

  # Pads a message using the PKCS #7 cryptographic message syntax.
  #
  # See: https://tools.ietf.org/html/rfc2315
  # See: `pkcs7_unpad/1`
  defp pkcs7_pad(message) do
    bytes_remaining = rem(byte_size(message), 16)
    padding_size = 16 - bytes_remaining
    message <> :binary.copy(<<padding_size>>, padding_size)
  end

  # Unpads a message using the PKCS #7 cryptographic message syntax.
  #
  # See: https://tools.ietf.org/html/rfc2315
  # See: `pkcs7_pad/1`
  defp pkcs7_unpad(<<>>),
    do: :error
  defp pkcs7_unpad(message) do
    padding_size = :binary.last(message)
    if padding_size <= 16 do
      message_size = byte_size(message)
      if binary_part(message, message_size, -padding_size) === :binary.copy(<<padding_size>>, padding_size) do
        {:ok, binary_part(message, 0, message_size - padding_size)}
      else
        :error
      end
    else
      :error
    end
  end

  defp encoding_to_key_length("A128CBC-HS256"), do: 32
  defp encoding_to_key_length("A192CBC-HS384"), do: 48
  defp encoding_to_key_length("A256CBC-HS512"), do: 64

  defp bit_size_to_cipher(128), do: :aes_cbc128
  defp bit_size_to_cipher(192), do: :aes_cbc192
  defp bit_size_to_cipher(256), do: :aes_cbc256
end
