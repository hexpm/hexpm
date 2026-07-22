defmodule Hexpm.Accounts.SSO.Connection do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_connections" do
    field :issuer, :string
    field :client_id, :string
    field :client_secret, :string, redact: true
    field :pending_client_secret, :string, redact: true
    field :discovery_document, :map
    field :jwks_document, :map
    field :discovery_expires_at, :utc_datetime_usec
    field :jwks_expires_at, :utc_datetime_usec
    field :metadata_expires_at, :utc_datetime_usec
    field :version, :integer, default: 1
    field :pending_client_secret_version, :integer
    field :tested_at, :utc_datetime_usec
    field :pending_client_secret_tested_at, :utc_datetime_usec
    field :enabled_at, :utc_datetime_usec

    belongs_to :organization, Organization
    has_many :identities, Hexpm.Accounts.SSO.Identity
    has_many :transactions, Hexpm.Accounts.SSO.Transaction
    has_many :notifications, Hexpm.Accounts.SSO.Notification
    has_many :failures, Hexpm.Accounts.SSO.Failure

    timestamps()
  end

  def credentials_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:organization_id, :issuer, :client_id, :client_secret])
    |> validate_required([:organization_id, :issuer, :client_id, :client_secret])
    |> validate_length(:issuer, max: 2_048)
    |> validate_length(:client_id, max: 1_024)
    |> validate_length(:client_secret, max: 4_096)
  end

  def configuration_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :organization_id,
      :issuer,
      :client_id,
      :client_secret,
      :discovery_document,
      :jwks_document,
      :discovery_expires_at,
      :jwks_expires_at,
      :metadata_expires_at,
      :version,
      :pending_client_secret_version,
      :tested_at,
      :pending_client_secret,
      :pending_client_secret_tested_at,
      :enabled_at
    ])
    |> validate_required([
      :organization_id,
      :issuer,
      :client_id,
      :client_secret,
      :discovery_document,
      :jwks_document,
      :discovery_expires_at,
      :jwks_expires_at,
      :metadata_expires_at,
      :version
    ])
    |> validate_length(:issuer, max: 2_048)
    |> validate_length(:client_id, max: 1_024)
    |> validate_length(:client_secret, max: 4_096)
    |> unique_constraint(:organization_id)
  end

  def rotation_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :pending_client_secret,
      :pending_client_secret_version,
      :pending_client_secret_tested_at
    ])
    |> validate_required([:pending_client_secret])
    |> validate_length(:pending_client_secret, max: 4_096)
  end

  def enabled?(%__MODULE__{enabled_at: enabled_at}), do: not is_nil(enabled_at)
end
