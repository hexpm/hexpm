defmodule Hexpm.Accounts.SSO.Transaction do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_transactions" do
    field :state_hash, :binary, redact: true
    field :raw_state, :string, virtual: true, redact: true
    field :nonce, :string, redact: true
    field :code_verifier, :string, redact: true
    field :kind, :string
    field :secret_slot, :string
    field :connection_version, :integer
    field :secret_version, :integer
    field :redirect_uri, :string
    field :return_path, :string
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
    field :issuer, :string
    field :subject, :string, redact: true
    field :provider_email, :string, redact: true
    field :link_token_hash, :binary, redact: true
    field :linked_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec

    belongs_to :connection, Hexpm.Accounts.SSO.Connection
    belongs_to :user, User

    timestamps()
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :connection_id,
      :user_id,
      :state_hash,
      :nonce,
      :code_verifier,
      :kind,
      :secret_slot,
      :connection_version,
      :secret_version,
      :redirect_uri,
      :return_path,
      :expires_at
    ])
    |> validate_required([
      :connection_id,
      :state_hash,
      :nonce,
      :code_verifier,
      :kind,
      :secret_slot,
      :connection_version,
      :secret_version,
      :redirect_uri,
      :expires_at
    ])
    |> validate_inclusion(:kind, ~w(login test))
    |> validate_inclusion(:secret_slot, ~w(active pending))
    |> unique_constraint(:state_hash)
  end

  def consume_changeset(transaction, attrs) do
    cast(transaction, attrs, [
      :consumed_at,
      :issuer,
      :subject,
      :provider_email,
      :link_token_hash,
      :linked_at,
      :cancelled_at,
      :nonce,
      :code_verifier,
      :user_id
    ])
  end
end
