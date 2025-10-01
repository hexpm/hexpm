defmodule Hexpm.OAuth.Client do
  use Hexpm.Schema

  alias Hexpm.Permissions

  @derive {Phoenix.Param, key: :client_id}

  @primary_key {:client_id, :binary_id, autogenerate: false}

  schema "oauth_clients" do
    field :client_secret, :string
    field :name, :string
    field :client_type, :string
    field :allowed_grant_types, {:array, :string}
    field :redirect_uris, {:array, :string}
    field :allowed_scopes, {:array, :string}

    timestamps()
  end

  @valid_client_types ~w(public confidential)
  @valid_grant_types ~w(authorization_code urn:ietf:params:oauth:grant-type:device_code refresh_token urn:ietf:params:oauth:grant-type:token-exchange)

  def changeset(client, attrs) do
    client
    |> cast(attrs, [
      :client_id,
      :client_secret,
      :name,
      :client_type,
      :allowed_grant_types,
      :redirect_uris,
      :allowed_scopes
    ])
    |> validate_required([:client_id, :name, :client_type])
    |> validate_inclusion(:client_type, @valid_client_types)
    |> validate_grant_types()
    |> validate_scopes()
    |> validate_client_secret_required()
    |> unique_constraint(:client_id)
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  defp validate_grant_types(changeset) do
    validate_change(changeset, :allowed_grant_types, fn :allowed_grant_types, grant_types ->
      invalid_types = Enum.reject(grant_types, &(&1 in @valid_grant_types))

      case invalid_types do
        [] ->
          []

        _ ->
          [allowed_grant_types: "contains invalid grant types: #{Enum.join(invalid_types, ", ")}"]
      end
    end)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :allowed_scopes, fn :allowed_scopes, scopes ->
      case Permissions.validate_scopes(scopes) do
        :ok -> []
        {:error, message} -> [allowed_scopes: message]
      end
    end)
  end

  defp validate_client_secret_required(changeset) do
    client_type = get_field(changeset, :client_type)
    client_secret = get_field(changeset, :client_secret)

    if client_type == "confidential" && is_nil(client_secret) do
      add_error(changeset, :client_secret, "is required for confidential clients")
    else
      changeset
    end
  end
end
