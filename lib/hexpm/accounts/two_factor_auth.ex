defmodule Hexpm.Accounts.TwoFactorAuth do
  def qr_code_content(user) do
    secret = Map.fetch!(user.tfa, :secret)
    "otpauth://totp/#{user.username}?issuer=hex.pm&secret=#{secret}"
  end

  def qr_code_svg(content) do
    content |> EQRCode.encode() |> EQRCode.svg(width: 400)
  end

  def generate_secret() do
    32 |> :crypto.strong_rand_bytes() |> Base.encode32() |> String.slice(0..15)
  end

  # addwindow 1 creates a token 30 seconds ahead
  def time_based_token(secret) do
    :pot.totp(secret, addwindow: 1)
  end

  # Check a token 30 seconds ahead and within a margin of error of 1 second
  def token_valid?(secret, token) do
    :pot.valid_totp(token, secret, window: 1, addwindow: 1)
  end
end
