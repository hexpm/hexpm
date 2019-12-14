defmodule Hexpm.Accounts.RecoveryCode do
  use Hexpm.Schema

  @derive {Jason.Encoder, only: []}

  @primary_key false
  embedded_schema do
    field :code, :string
    field :used_at, :utc_datetime_usec
  end

  def changeset(recovery_code, params) do
    cast(recovery_code, params, [:code, :used_at])
  end
end
