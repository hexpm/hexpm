defmodule Hexpm.Accounts.SSO.Identity do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_identities" do
    field :issuer, :string
    field :subject, :string, redact: true
    field :provider_email, :string, redact: true

    belongs_to :organization, Organization
    belongs_to :connection, Hexpm.Accounts.SSO.Connection
    belongs_to :user, User

    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :organization_id,
      :connection_id,
      :user_id,
      :issuer,
      :subject,
      :provider_email
    ])
    |> validate_required([:organization_id, :connection_id, :user_id, :issuer, :subject])
    |> validate_length(:subject, max: 255)
    |> validate_length(:provider_email, max: 320)
    |> unique_constraint([:connection_id, :issuer, :subject],
      name: :organization_sso_identities_external_identity_index
    )
    |> unique_constraint([:connection_id, :user_id])
    |> foreign_key_constraint(:connection_id,
      name: :organization_sso_identities_connection_organization_fkey
    )
  end
end
