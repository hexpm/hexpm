defmodule Hexpm.Accounts.TFA do
  use Hexpm.Schema

  @primary_key false
  embedded_schema do
    field :secret, :string
    field :tfa_enabled, :boolean, default: false
    field :app_enabled, :boolean, default: false
    embeds_many :recovery_codes, Hexpm.Accounts.RecoveryCode
  end

  def changeset(tfa, params) do
    tfa
    |> cast(params, ~w(secret app_enabled tfa_enabled)a)
    |> cast_embed(:recovery_codes)
  end

  def generate_secret() do
    10
    |> :crypto.strong_rand_bytes()
    |> Base.encode32()
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
