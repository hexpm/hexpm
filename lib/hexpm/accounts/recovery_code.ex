defmodule Hexpm.Accounts.RecoveryCode do
  use Hexpm.Schema

  schema "user_recovery_codes" do
    field :code_digest, :string
    field :used_at, :utc_datetime_usec
    timestamps()

    belongs_to :user, User
  end

  def changeset(recovery_code, params) do
    cast(recovery_code, params, [:code_digest, :used_at])
    |> validate_required([:code_digest, :used_at])
    |> unique_constraint(:code_digest)
  end

end
