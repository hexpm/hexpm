defmodule Hexpm.Accounts.SSO.Authorization do
  @moduledoc """
  A request from a session to be authenticated against its organizations'
  identity providers, and the short-lived URI its owner opens to do it.

  The session that asks is the session that gets the organization access, which
  is what lets a terminal renew a lapsed binding with a browser visit rather
  than a whole new device authorization.
  """

  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_authorizations" do
    field :code_hash, :binary, redact: true
    field :raw_code, :string, virtual: true, redact: true
    field :organization_ids, {:array, :integer}, default: []
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    belongs_to :user, User
    belongs_to :user_session, Hexpm.UserSession

    timestamps()
  end

  def changeset(authorization, attrs) do
    authorization
    |> cast(attrs, [:user_id, :user_session_id, :code_hash, :organization_ids, :expires_at])
    |> validate_required([:user_id, :user_session_id, :code_hash, :organization_ids, :expires_at])
    |> unique_constraint(:code_hash)
  end
end
