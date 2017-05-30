defmodule Hexpm.Crypto.PKCS5 do
  @moduledoc ~S"""
  PKCS #5: Password-Based Cryptography Specification Version 2.0

  See: https://tools.ietf.org/html/rfc2898
  """

  def pbkdf2(password, salt, iterations, derived_key_length, hash)
  when is_binary(password) and
       is_binary(salt) and
       is_integer(iterations) and iterations >= 1 and
       is_integer(derived_key_length) and derived_key_length >= 0 do
    hash_length = byte_size(:crypto.hmac(hash, <<>>, <<>>))
    if derived_key_length > (0xFFFFFFFF * hash_length) do
      raise ArgumentError, "derived key too long"
    else
      rounds = ceildiv(derived_key_length, hash_length)
      <<derived_key::binary-size(derived_key_length), _::binary>> =
        pbkdf2_iterate(password, salt, iterations, hash, 1, rounds, "")
      derived_key
    end
  end

  defp ceildiv(a, b) do
    div(a, b) + (if rem(a, b) === 0, do: 0, else: 1)
  end

  defp pbkdf2_iterate(password, salt, iterations, hash, rounds, rounds, derived_keying_material),
    do: derived_keying_material <> pbkdf2_exor(password, salt, iterations, hash, 1, rounds, <<>>, <<>>)
  defp pbkdf2_iterate(password, salt, iterations, hash, counter, rounds, derived_keying_material) do
    derived_keying_material = derived_keying_material <> pbkdf2_exor(password, salt, iterations, hash, 1, counter, <<>>, <<>>)
    pbkdf2_iterate(password, salt, iterations, hash, counter + 1, rounds, derived_keying_material)
  end

  defp pbkdf2_exor(_password, _salt, iterations, _hash, i, _counter, _prev, curr) when i > iterations,
    do: curr
  defp pbkdf2_exor(password, salt, iterations, hash, i = 1, counter, <<>>, <<>>) do
    next = :crypto.hmac(hash, password, << salt :: binary, counter :: 1-unsigned-big-integer-unit(32) >>)
    pbkdf2_exor(password, salt, iterations, hash, i + 1, counter, next, next)
  end
  defp pbkdf2_exor(password, salt, iterations, hash, i, counter, prev, curr) do
    next = :crypto.hmac(hash, password, prev)
    curr = :crypto.exor(next, curr)
    pbkdf2_exor(password, salt, iterations, hash, i + 1, counter, next, curr)
  end
end
