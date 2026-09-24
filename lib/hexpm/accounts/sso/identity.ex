defmodule Hexpm.Accounts.SSO.Identity do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_identities" do
    field :issuer, :string
    field :subject, :string, redact: true
    field :provider_email, :string, redact: true

    # Kept on the identity rather than derived from organization_sso_sessions.
    # Those cascade away with the browser session that produced them, so a
    # member who logged out read as never having authenticated.
    field :last_authenticated_at, :utc_datetime_usec

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
    |> validate_length(:issuer, count: :bytes, max: 2_048)
    |> validate_length(:subject, count: :bytes, max: 255)
    |> validate_length(:provider_email, count: :bytes, max: 255)
    |> unique_constraint([:connection_id, :issuer, :subject],
      name: :organization_sso_identities_external_identity_index
    )
    |> unique_constraint([:connection_id, :user_id])
    |> foreign_key_constraint(:connection_id,
      name: :organization_sso_identities_connection_organization_fkey
    )
  end
end
