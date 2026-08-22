defmodule Hexpm.Accounts.SSO.Failure do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_failures" do
    field :stage, :string
    field :code, :string

    belongs_to :connection, Hexpm.Accounts.SSO.Connection
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(failure, attrs) do
    failure
    |> cast(attrs, [:connection_id, :stage, :code, :user_id])
    |> validate_required([:connection_id, :stage, :code])
  end
end
