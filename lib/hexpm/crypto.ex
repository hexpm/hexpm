defmodule Hexpm.Crypto do
  alias Hexpm.Crypto.Encryption

  def encrypt(plain_text, password, tag \\ "") do
    Encryption.encrypt({tag, plain_text}, %{
      alg: "PBES2-HS512",
      enc: "A128CBC-HS256",
      p2c: 32_768,
      p2s: :crypto.strong_rand_bytes(16)
    }, [
      password: password
    ])
  end

  def decrypt(cipher_text, password, tag \\ "") do
    Encryption.decrypt({tag, cipher_text}, [
      password: password
    ])
  end

  def base64url_encode(binary) do
    try do
      Base.url_encode64(binary, padding: false)
    catch
      _,_ ->
        binary
        |> Base.encode64()
        |> urlsafe_encode64(<<>>)
    end
  end

  def base64url_decode(binary) do
    try do
      Base.url_decode64(binary, padding: false)
    catch
      _,_ ->
        try do
          binary = urlsafe_decode64(binary, <<>>)
          binary =
            case rem(byte_size(binary), 4) do
              2 -> binary <> "=="
              3 -> binary <> "="
              _ -> binary
            end
          Base.decode64(binary)
        catch
          _,_ ->
            :error
        end
    end
  end

  ## Internal
  defp urlsafe_encode64(<< ?+, rest :: binary >>, acc),
    do: urlsafe_encode64(rest, << acc :: binary, ?- >>)
  defp urlsafe_encode64(<< ?/, rest :: binary >>, acc),
    do: urlsafe_encode64(rest, << acc :: binary, ?_ >>)
  defp urlsafe_encode64(<< ?=, rest :: binary >>, acc),
    do: urlsafe_encode64(rest, acc)
  defp urlsafe_encode64(<< c, rest :: binary >>, acc),
    do: urlsafe_encode64(rest, << acc :: binary, c >>)
  defp urlsafe_encode64(<<>>, acc),
    do: acc

  defp urlsafe_decode64(<< ?-, rest :: binary >>, acc),
    do: urlsafe_decode64(rest, << acc :: binary, ?+ >>)
  defp urlsafe_decode64(<< ?_, rest :: binary >>, acc),
    do: urlsafe_decode64(rest, << acc :: binary, ?/ >>)
  defp urlsafe_decode64(<< c, rest :: binary >>, acc),
    do: urlsafe_decode64(rest, << acc :: binary, c >>)
  defp urlsafe_decode64(<<>>, acc),
    do: acc
end
