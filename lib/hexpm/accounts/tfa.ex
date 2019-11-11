defmodule Hexpm.Accounts.TFA do
  use Hexpm.Schema

  @primary_key false
  embedded_schema do
    field :secret, :string
    embeds_many :recovery_codes, Hexpm.Accounts.RecoveryCode
  end

  def changeset(tfa, params) do
    tfa
    |> cast(params, [:secret])
    |> cast_embed(:recovery_codes)
  end
end
