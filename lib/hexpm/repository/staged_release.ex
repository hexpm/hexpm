defmodule Hexpm.Repository.StagedRelease do
  use Hexpm.Schema

  schema "staged_releases" do
    field :name, :string
    field :version, Hexpm.Version
    field :kind, :string
    field :meta, :map, default: %{}
    field :replace, :boolean, default: false
    field :publication, :map
    field :inner_checksum, :binary
    field :outer_checksum, :binary
    field :storage_key, :string
    field :docs_checksum, :binary
    field :docs_storage_key, :string
    field :credential_type, :string
    field :credential_name, :string
    field :oidc_claims, :map
    field :expires_at, :utc_datetime_usec
    field :audit_data, :map
    belongs_to :repository, Repository
    belongs_to :user, User
    belongs_to :organization, Organization
    belongs_to :key, Key
    belongs_to :workload_identity, Hexpm.WorkloadIdentities.WorkloadIdentity
    timestamps()
  end

  def changeset(staged, attrs) do
    staged
    |> cast(attrs, __schema__(:fields) -- [:id, :inserted_at, :updated_at])
    |> validate_required([
      :repository_id,
      :name,
      :version,
      :kind,
      :credential_type,
      :credential_name,
      :expires_at,
      :audit_data
    ])
    |> unique_constraint([:repository_id, :name, :version, :kind])
  end

  def checksum(staged) do
    :crypto.hash(:sha256, [staged.outer_checksum || <<>>, staged.docs_checksum || <<>>])
    |> Base.encode16(case: :lower)
  end
end
