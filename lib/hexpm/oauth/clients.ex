defmodule Hexpm.OAuth.Clients do
  use Hexpm.Context

  alias Hexpm.OAuth.Client
  alias Hexpm.Permissions

  @doc """
  Gets a client by client_id.

  Looks up from the in-memory cache first (populated at application startup
  via `load_cache/0`), falls back to a database query on cache miss.
  """
  def get(client_id) do
    cache = :persistent_term.get({__MODULE__, :cache}, %{})

    case Map.fetch(cache, client_id) do
      {:ok, client} -> client
      :error -> Repo.get(Client, client_id)
    end
  end

  @doc """
  Loads all OAuth clients into the in-memory cache.
  Called at application startup and after mutations.
  """
  def load_cache do
    clients = Repo.all(Client)
    cache = Map.new(clients, fn client -> {client.client_id, client} end)
    :persistent_term.put({__MODULE__, :cache}, cache)
  end

  @doc """
  Creates a new OAuth client.
  """
  def create(attrs) do
    result =
      %Client{}
      |> Client.changeset(attrs)
      |> Repo.insert()

    if match?({:ok, _}, result), do: load_cache()
    result
  end

  @doc """
  Updates an OAuth client.
  """
  def update(%Client{} = client, attrs) do
    result =
      client
      |> Client.changeset(attrs)
      |> Repo.update()

    if match?({:ok, _}, result), do: load_cache()
    result
  end

  @doc """
  Deletes an OAuth client.
  """
  def delete(%Client{} = client) do
    result = Repo.delete(client)
    if match?({:ok, _}, result), do: load_cache()
    result
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
  def supports_scopes?(%Client{allowed_scopes: allowed_scopes}, requested_scopes) do
    Enum.all?(requested_scopes, fn scope ->
      scope in allowed_scopes or api_scope_allowed_by_full_api?(scope, allowed_scopes) or
        resource_scope_allowed_by_base?(scope, allowed_scopes)
    end)
  end

  defp api_scope_allowed_by_full_api?(scope, allowed_scopes) do
    scope in ["api:read", "api:write"] and "api" in allowed_scopes
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

  Supports wildcard patterns in the host, e.g.:
  - `https://*.hexdocs.pm/oauth/callback` matches `https://acme.hexdocs.pm/oauth/callback`
  - The wildcard `*` matches lowercase letters, digits, `_` and `-` within one
    host label, and the resulting host must be a valid hostname (organization
    names can contain `_`)

  For wildcard patterns the scheme, port, path, query and fragment must equal
  the pattern's, and URIs with userinfo, backslashes, tabs or newlines never
  match.
  """
  def valid_redirect_uri?(%Client{redirect_uris: []}, _uri), do: false

  def valid_redirect_uri?(%Client{redirect_uris: allowed_uris}, uri) when is_binary(uri) do
    Enum.any?(allowed_uris, &uri_matches?(&1, uri))
  end

  def valid_redirect_uri?(%Client{}, _uri), do: false

  @host ~r/\A[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?(\.[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?)*\z/

  defp uri_matches?(pattern, uri) do
    if String.contains?(pattern, "*") do
      wildcard_matches?(URI.parse(pattern), uri)
    else
      pattern == uri
    end
  end

  # WHATWG strips tabs and newlines and reads `\\` as `/` in special schemes,
  # `URI.parse/1` does neither, so a URI holding one can parse to a different
  # authority in a browser.
  defp wildcard_matches?(pattern, uri) do
    parsed = URI.parse(uri)

    not String.contains?(uri, ["\\", "\t", "\r", "\n"]) and
      parsed.userinfo == nil and
      pattern.userinfo == nil and
      is_binary(parsed.host) and
      parsed.scheme == pattern.scheme and
      parsed.port == pattern.port and
      parsed.path == pattern.path and
      parsed.query == pattern.query and
      parsed.fragment == pattern.fragment and
      host_matches?(pattern.host, String.downcase(parsed.host))
  end

  defp host_matches?(pattern_host, host) do
    Regex.match?(@host, host) and Regex.match?(host_regex(pattern_host), host)
  end

  defp host_regex(pattern_host) do
    pattern_host
    |> Regex.escape()
    |> String.replace("\\*", "[a-z0-9_-]+")
    |> then(&Regex.compile!("\\A#{&1}\\z"))
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
