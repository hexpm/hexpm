defmodule Hexpm.Accounts.SSO.Domain do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_domains" do
    field :domain, :string
    field :challenge, :string
    field :challenge_generation, :integer, default: 1
    field :state, :string, default: "pending"
    field :verified_at, :utc_datetime_usec
    field :last_checked_at, :utc_datetime_usec
    field :valid_until, :utc_datetime_usec
    field :invalidated_at, :utc_datetime_usec
    field :discovery_enabled, :boolean, default: false
    field :automatic_linking_enabled, :boolean, default: false

    belongs_to :organization, Organization

    timestamps()
  end

  def create_changeset(domain, attrs) do
    domain
    |> cast(attrs, [
      :organization_id,
      :domain,
      :challenge,
      :challenge_generation,
      :state
    ])
    |> validate_required([
      :organization_id,
      :domain,
      :challenge,
      :challenge_generation,
      :state
    ])
    |> validate_length(:domain, max: 253)
    |> validate_length(:challenge, max: 255)
    |> validate_number(:challenge_generation, greater_than: 0)
    |> validate_inclusion(:state, ~w(pending verified invalid))
    |> unique_constraint([:organization_id, :domain])
    |> unique_constraint(:challenge)
  end

  def policy_changeset(domain, attrs) do
    cast(domain, attrs, [:discovery_enabled, :automatic_linking_enabled])
  end
end
