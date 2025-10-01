defmodule Hexpm.OAuth.Token do
  use Hexpm.Schema

  alias Hexpm.Accounts.User
  alias Hexpm.Permissions
  alias Hexpm.OAuth.Session

  schema "oauth_tokens" do
    field :jti, :string
    field :refresh_jti, :string
    field :token_type, :string, default: "bearer"
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :refresh_token_expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :grant_type, :string
    field :grant_reference, :string

    # Virtual fields for JWT tokens (not persisted)
    field :access_token, :string, virtual: true
    field :refresh_token, :string, virtual: true

    belongs_to :user, User
    belongs_to :parent_token, __MODULE__
    belongs_to :client, Hexpm.OAuth.Client, references: :client_id, type: :binary_id
    belongs_to :session, Session

    timestamps()
  end

  @valid_grant_types ~w(authorization_code urn:ietf:params:oauth:grant-type:device_code refresh_token urn:ietf:params:oauth:grant-type:token-exchange)

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :jti,
      :refresh_jti,
      :token_type,
      :scopes,
      :expires_at,
      :refresh_token_expires_at,
      :revoked_at,
      :grant_type,
      :grant_reference,
      :parent_token_id,
      :session_id,
      :user_id,
      :client_id,
      :access_token,
      :refresh_token
    ])
    |> validate_required([
      :jti,
      :token_type,
      :scopes,
      :expires_at,
      :grant_type,
      :user_id,
      :client_id
    ])
    |> validate_inclusion(:grant_type, @valid_grant_types)
    |> validate_scopes()
    |> unique_constraint(:jti)
    |> unique_constraint(:refresh_jti)
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      case Permissions.validate_scopes(scopes) do
        :ok -> []
        {:error, message} -> [scopes: message]
      end
    end)
  end
end
