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
    # A diagnostic is written after the connection has been read, and a
    # connection that was deleted in between leaves nothing to attach it to.
    # Losing the entry is the outcome; raising over it is not.
    |> foreign_key_constraint(:connection_id)
  end
end
