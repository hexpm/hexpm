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
  @valid_grant_types ~w(authorization_code urn:ietf:params:oauth:grant-type:device_code refresh_token client_credentials)

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
    |> validate_redirect_uris()
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
      invalid_scopes = Enum.reject(scopes, &Permissions.valid_client_allowed_scope?/1)

      case invalid_scopes do
        [] -> []
        _ -> [allowed_scopes: "contains invalid scopes: #{Enum.join(invalid_scopes, ", ")}"]
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

  defp validate_redirect_uris(changeset) do
    validate_change(changeset, :redirect_uris, fn :redirect_uris, uris ->
      Enum.flat_map(uris, &validate_redirect_uri/1)
    end)
  end

  defp validate_redirect_uri(uri) do
    cond do
      not valid_uri?(uri) ->
        [redirect_uris: "#{uri} is not a valid URI"]

      String.contains?(uri, "*") and count_wildcards(uri) > 1 ->
        [redirect_uris: "#{uri} contains multiple wildcards"]

      String.contains?(uri, "*") and not wildcard_in_host?(uri) ->
        [redirect_uris: "#{uri} has wildcard outside of host"]

      String.contains?(uri, "*") and not String.starts_with?(uri, "https://") ->
        [redirect_uris: "#{uri} wildcard redirect URIs must use HTTPS"]

      String.contains?(uri, "*") and not sufficient_domain_segments?(uri) ->
        [redirect_uris: "#{uri} wildcard must have at least domain.tld after *"]

      true ->
        []
    end
  end

  defp valid_uri?(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host} when not is_nil(scheme) and not is_nil(host) -> true
      _ -> false
    end
  end

  defp count_wildcards(string) do
    string |> String.graphemes() |> Enum.count(&(&1 == "*"))
  end

  defp wildcard_in_host?(uri) do
    case URI.parse(uri) do
      %URI{host: host} when not is_nil(host) -> String.contains?(host, "*")
      _ -> false
    end
  end

  defp sufficient_domain_segments?(uri) do
    case URI.parse(uri) do
      %URI{host: host} when not is_nil(host) ->
        # After removing *, need at least 2 segments (domain.tld)
        # e.g., *.example.com → .example.com → ["", "example", "com"] → 2+ non-empty
        host
        |> String.replace("*", "")
        |> String.split(".")
        |> Enum.reject(&(&1 == ""))
        |> length() >= 2

      _ ->
        false
    end
  end
end
