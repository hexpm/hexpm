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
    field :jit_seat_policy, :string
    field :jit_role, :string, default: "read"

    belongs_to :organization, Organization
    belongs_to :configured_by_user, User
    has_many :identities, Hexpm.Accounts.SSO.Identity
    has_many :transactions, Hexpm.Accounts.SSO.Transaction
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
      :configured_by_user_id,
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

  @jit_seat_policies ~w(block expand)
  @jit_roles ~w(admin write read)

  def jit_seat_policies, do: @jit_seat_policies

  def jit_roles, do: @jit_roles

  @doc """
  Turns just-in-time membership on or off. `jit_seat_policy` is required to turn
  it on and there is no default, because auto-expanding a subscription is a
  billing change and nobody should get it without having asked for it.
  """
  def jit_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:jit_seat_policy, :jit_role])
    |> update_change(:jit_seat_policy, &nilify_blank/1)
    |> validate_required([:jit_role])
    |> validate_inclusion(:jit_seat_policy, @jit_seat_policies)
    |> validate_inclusion(:jit_role, @jit_roles)
  end

  def enabled?(%__MODULE__{enabled_at: enabled_at}), do: not is_nil(enabled_at)

  def jit_enabled?(%__MODULE__{jit_seat_policy: policy}), do: policy in @jit_seat_policies

  defp nilify_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nilify_blank(value), do: value
end
