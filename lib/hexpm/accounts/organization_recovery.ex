defmodule Hexpm.Accounts.OrganizationRecovery do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_recoveries" do
    field :billing_email, :string
    field :card_brand, :string
    field :card_last4, :string
    field :token_hash, :binary, redact: true
    field :raw_token, :string, virtual: true, redact: true
    field :expires_at, :utc_datetime_usec
    field :verified_at, :utc_datetime_usec
    field :completes_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :canceled_at, :utc_datetime_usec

    belongs_to :organization, Organization
    belongs_to :user, User
    belongs_to :old_admin, User
    belongs_to :started_by_user, User

    timestamps()
  end

  def changeset(recovery, attrs) do
    recovery
    |> cast(attrs, [
      :organization_id,
      :user_id,
      :old_admin_id,
      :started_by_user_id,
      :billing_email,
      :card_brand,
      :card_last4,
      :token_hash,
      :expires_at
    ])
    |> validate_required([:organization_id, :user_id, :billing_email, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
    |> unique_constraint(:organization_id, name: :organization_recoveries_open_index)
  end

  def verify_changeset(recovery, now, completes_at) do
    change(recovery, verified_at: now, completes_at: completes_at)
  end

  def complete_changeset(recovery, now), do: change(recovery, completed_at: now)

  def cancel_changeset(recovery, now), do: change(recovery, canceled_at: now)

  def open?(%__MODULE__{completed_at: nil, canceled_at: nil}), do: true
  def open?(%__MODULE__{}), do: false
end
