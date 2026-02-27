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
    Enum.all?(requested_scopes, fn scope ->
      scope in allowed_scopes or resource_scope_allowed_by_base?(scope, allowed_scopes)
    end)
  end

  # Check if a resource-specific scope (e.g., "docs:acme") is allowed
  # when the client has the base scope (e.g., "docs") in allowed_scopes.
  defp resource_scope_allowed_by_base?(scope, allowed_scopes) do
    if Permissions.resource_specific_scope?(scope) do
      [base, _resource] = String.split(scope, ":", parts: 2)
      base in allowed_scopes
    else
      false
    end
  end

  @doc """
  Validates that the redirect URI is allowed for this client.

  Supports wildcard patterns in the subdomain position, e.g.:
  - `https://*.hexdocs.pm/oauth/callback` matches `https://acme.hexdocs.pm/oauth/callback`
  - The wildcard `*` matches a single subdomain segment (no dots)
  """
  def valid_redirect_uri?(%Client{redirect_uris: []}, _uri), do: false

  def valid_redirect_uri?(%Client{redirect_uris: allowed_uris}, uri) do
    Enum.any?(allowed_uris, &uri_matches?(&1, uri))
  end

  defp uri_matches?(pattern, uri) do
    if String.contains?(pattern, "*") do
      # Normalize default ports: https://foo.com:443 → https://foo.com
      normalized_uri = strip_default_port(uri)

      # Convert wildcard to regex: * → [^.]+ (single subdomain segment)
      pattern
      |> Regex.escape()
      |> String.replace("\\*", "[^.]+")
      |> then(&Regex.match?(~r/^#{&1}$/, normalized_uri))
    else
      pattern == uri
    end
  end

  defp strip_default_port(uri) do
    case URI.parse(uri) do
      %URI{scheme: "https", port: 443} = parsed -> URI.to_string(%{parsed | port: nil})
      %URI{scheme: "http", port: 80} = parsed -> URI.to_string(%{parsed | port: nil})
      _ -> uri
    end
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
