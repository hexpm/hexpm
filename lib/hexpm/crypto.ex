defmodule Hexpm.Crypto do
  import Hexpm.Crypto.Pbkdf2

  def encrypt(secret, plain, tag \\ "") do
    salt = gen_salt()
    <<key::binary-32, iv::binary-16>> = pbkdf2(secret, salt, iterations(), 48, :sha256)
    plain = pad(tag <> plain, 16)
    cipher = :crypto.block_encrypt(:aes_cbc256, key, iv, plain)

    Base.encode16(salt <> cipher)
  end

  def decrypt(secret, encrypted, tag \\ "") do
    {:ok, <<salt::binary-16, cipher::binary>>} = Base.decode16(encrypted)
    <<key::binary-32, iv::binary-16>> = pbkdf2(secret, salt, iterations(), 48, :sha256)

    :crypto.block_decrypt(:aes_cbc256, key, iv, cipher)
    |> unpad(16)
    |> untag(tag)
  end

  defp gen_salt(), do: :crypto.strong_rand_bytes(16)
  defp iterations(), do: Application.get_env(:hexpm, :totp_encryption_rounds)

  defp pad(plain, size) do
    byte = size - rem(byte_size(plain), size)
    [plain, :lists.duplicate(byte, byte)]
  end

  defp unpad(cipher, size) do
    cipher_size = byte_size(cipher)
    byte = :binary.at(cipher, cipher_size-1)

    if rem(cipher_size, size) == 0 and byte <= size do
      padding = :lists.duplicate(byte, byte) |> IO.iodata_to_binary
      binary_size = cipher_size - byte
      <<binary::binary-size(binary_size), rest::binary-size(byte)>> = cipher
      if padding == rest do
        {:ok, binary}
      else
        :error
      end
    else
      :error
    end
  end

  defp untag({:ok, plain}, tag) do
    tag_size = byte_size(tag)
    case plain do
      <<^tag::binary-size(tag_size), plain::binary>> ->
        {:ok, plain}
      _ ->
        :error
    end
  end
  defp untag(:error, _tag), do: :error
end
