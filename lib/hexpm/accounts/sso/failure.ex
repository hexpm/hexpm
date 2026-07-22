defmodule Hexpm.Accounts.SSO.Failure do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_failures" do
    field :stage, :string
    field :code, :string
    field :details, :map, default: %{}

    belongs_to :connection, Hexpm.Accounts.SSO.Connection

    timestamps(updated_at: false)
  end

  def changeset(failure, attrs) do
    failure
    |> cast(attrs, [:connection_id, :stage, :code, :details])
    |> validate_required([:connection_id, :stage, :code, :details])
  end
end
