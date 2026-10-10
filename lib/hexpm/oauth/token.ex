defmodule Hexpm.OAuth.Token do
  use Hexpm.Schema

  alias Hexpm.Accounts.{Organization, User}
  alias Hexpm.Permissions
  alias Hexpm.UserSession

  schema "oauth_tokens" do
    field :jti, :string
    field :refresh_jti, :string
    field :refresh_token_hash, :string
    field :token_type, :string, default: "bearer"
    field :scopes, {:array, :string}, default: []
    field :granted_scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :refresh_token_expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :grant_type, :string
    field :grant_reference, :string

    # Virtual fields for JWT tokens (not persisted)
    field :access_token, :string, virtual: true
    field :refresh_token, :string, virtual: true

    field :organization_reauth_required, {:array, :map}, virtual: true, default: []

    belongs_to :user, User
    belongs_to :organization, Organization
    belongs_to :workload_identity, Hexpm.WorkloadIdentities.WorkloadIdentity
    belongs_to :client, Hexpm.OAuth.Client, references: :client_id, type: :binary_id
    belongs_to :user_session, UserSession

    embeds_one :oidc_claims, Hexpm.WorkloadIdentities.ClaimsSnapshot, on_replace: :delete

    timestamps()
  end

  @valid_grant_types ~w(authorization_code urn:ietf:params:oauth:grant-type:device_code refresh_token client_credentials workload_identity)

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :jti,
      :refresh_jti,
      :refresh_token_hash,
      :token_type,
      :scopes,
      :granted_scopes,
      :expires_at,
      :refresh_token_expires_at,
      :revoked_at,
      :grant_type,
      :grant_reference,
      :user_session_id,
      :user_id,
      :organization_id,
      :workload_identity_id,
      :client_id,
      :access_token,
      :refresh_token,
      :organization_reauth_required
    ])
    |> cast_embed(:oidc_claims)
    |> validate_required([
      :jti,
      :token_type,
      :scopes,
      :expires_at,
      :grant_type
    ])
    |> validate_client_present()
    |> validate_inclusion(:grant_type, @valid_grant_types)
    |> validate_subject_present()
    |> validate_scopes()
    |> unique_constraint(:jti)
    |> unique_constraint(:refresh_jti)
    |> unique_constraint(:refresh_token_hash)
    |> unique_constraint(:grant_reference,
      name: :oauth_tokens_device_code_grant_reference_client_id_index,
      message: "a live token already exists for this device code"
    )
    |> unique_constraint(:grant_reference,
      name: :oauth_tokens_workload_identity_grant_reference_index,
      message: "OIDC token has already been used"
    )
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  def valid_grant_types, do: @valid_grant_types

  defp validate_client_present(changeset) do
    if get_field(changeset, :grant_type) == "workload_identity" do
      changeset
    else
      validate_required(changeset, [:client_id])
    end
  end

  defp validate_subject_present(changeset) do
    user_id = get_field(changeset, :user_id)
    organization_id = get_field(changeset, :organization_id)
    workload_identity_id = get_field(changeset, :workload_identity_id)

    if is_nil(user_id) and is_nil(organization_id) and is_nil(workload_identity_id) do
      add_error(
        changeset,
        :workload_identity_id,
        "user, organization, or workload identity required"
      )
    else
      changeset
    end
  end

  defp validate_scopes(changeset) do
    changeset
    |> validate_scopes_field(:scopes)
    |> validate_scopes_field(:granted_scopes)
  end

  defp validate_scopes_field(changeset, field) do
    validate_change(changeset, field, fn ^field, scopes ->
      case Permissions.validate_scopes(scopes) do
        :ok -> []
        {:error, message} -> [{field, message}]
      end
    end)
  end
end
