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

  @doc """
  Validates that the client is allowed to use the specified grant type.
  """
  def supports_grant_type?(%__MODULE__{allowed_grant_types: grant_types}, grant_type) do
    grant_type in grant_types
  end

  @doc """
  Validates that the client is allowed to use the specified scopes.
  """
  def supports_scopes?(%__MODULE__{allowed_scopes: nil}, requested_scopes) do
    Permissions.validate_scopes(requested_scopes) == :ok
  end

  def supports_scopes?(%__MODULE__{allowed_scopes: allowed_scopes}, requested_scopes) do
    Enum.all?(requested_scopes, &(&1 in allowed_scopes))
  end

  @doc """
  Validates that the redirect URI is allowed for this client.
  """
  def valid_redirect_uri?(%__MODULE__{redirect_uris: []}, _uri), do: false

  def valid_redirect_uri?(%__MODULE__{redirect_uris: allowed_uris}, uri) do
    uri in allowed_uris
  end

  @doc """
  Checks if client authentication is required.
  """
  def requires_authentication?(%__MODULE__{client_type: "confidential"}), do: true
  def requires_authentication?(%__MODULE__{client_type: "public"}), do: false

  @doc """
  Validates client credentials.
  """
  def authenticate?(%__MODULE__{client_secret: secret}, provided_secret)
      when not is_nil(secret) do
    Bcrypt.verify_pass(provided_secret || "", secret)
  end

  def authenticate?(%__MODULE__{client_secret: nil}, _), do: true

  @doc """
  Generates a client secret for confidential clients.
  """
  def generate_client_secret do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a unique client ID.
  """
  def generate_client_id do
    Ecto.UUID.generate()
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
