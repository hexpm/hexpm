defmodule Hexpm.Accounts.TwoFactorAuth do
  def qr_code_content(user) do
    "otpauth://totp/#{user.username}?issuer=hex.pm&secret=#{user.auth_secret}"
  end

  def qr_code_svg(content) do
    content |> EQRCode.encode() |> EQRCode.svg(width: 400)
  end

  def generate_secret() do
    32 |> :crypto.strong_rand_bytes() |> Base.encode32() |> String.slice(0..15)
  end

  def time_based_token(secret) do
    :pot.totp(secret)
  end

  def token_valid?(secret, token) do
    :pot.valid_totp(token, secret)
  end
end
