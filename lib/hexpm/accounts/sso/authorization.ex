defmodule Hexpm.Accounts.SSO.Authorization do
  @moduledoc """
  A request bound to an account and an OAuth session for browser verification of
  organization SSO and 2FA requirements. Completing every check grants the
  verified access without extending the target session's expiry.
  """

  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_authorizations" do
    field :code_hash, :binary, redact: true
    field :raw_code, :string, virtual: true, redact: true
    field :organization_ids, {:array, :integer}, default: []
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
    field :redirect_uri, :string
    field :state, :string, redact: true

    belongs_to :user, User
    belongs_to :user_session, Hexpm.UserSession

    timestamps()
  end

  def changeset(authorization, attrs) do
    authorization
    |> cast(
      attrs,
      [
        :user_id,
        :user_session_id,
        :code_hash,
        :organization_ids,
        :expires_at,
        :redirect_uri,
        :state
      ],
      empty_values: []
    )
    |> validate_required([:user_id, :user_session_id, :code_hash, :organization_ids, :expires_at])
    |> unique_constraint(:code_hash)
  end
end
