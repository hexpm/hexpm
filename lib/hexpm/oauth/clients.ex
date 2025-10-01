defmodule Hexpm.OAuth.Clients do
  use Hexpm.Context

  alias Hexpm.OAuth.Client
  alias Hexpm.Permissions

  @doc """
  Gets a client by client_id.
  """
  def get(client_id) do
    Repo.get(Client, client_id)
  end

  @doc """
  Creates a new OAuth client.
  """
  def create(attrs) do
    %Client{}
    |> Client.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an OAuth client.
  """
  def update(%Client{} = client, attrs) do
    client
    |> Client.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an OAuth client.
  """
  def delete(%Client{} = client) do
    Repo.delete(client)
  end

  @doc """
  Validates that the client is allowed to use the specified grant type.
  """
  def supports_grant_type?(%Client{allowed_grant_types: grant_types}, grant_type) do
    grant_type in grant_types
  end

  @doc """
  Validates that the client is allowed to use the specified scopes.
  """
  def supports_scopes?(%Client{allowed_scopes: nil}, requested_scopes) do
    Permissions.validate_scopes(requested_scopes) == :ok
  end

  def supports_scopes?(%Client{allowed_scopes: allowed_scopes}, requested_scopes) do
    Enum.all?(requested_scopes, &(&1 in allowed_scopes))
  end

  @doc """
  Validates that the redirect URI is allowed for this client.
  """
  def valid_redirect_uri?(%Client{redirect_uris: []}, _uri), do: false

  def valid_redirect_uri?(%Client{redirect_uris: allowed_uris}, uri) do
    uri in allowed_uris
  end

  @doc """
  Checks if client authentication is required.
  """
  def requires_authentication?(%Client{client_type: "confidential"}), do: true
  def requires_authentication?(%Client{client_type: "public"}), do: false

  @doc """
  Validates client credentials.
  """
  def authenticate?(%Client{client_secret: secret}, provided_secret)
      when not is_nil(secret) do
    Plug.Crypto.secure_compare(secret, provided_secret || "")
  end

  def authenticate?(%Client{client_secret: nil}, _), do: true

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
end
