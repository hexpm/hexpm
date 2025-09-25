defmodule Hexpm.OAuth.TokenExchange do
  @moduledoc """
  Implementation of RFC 8693 OAuth 2.0 Token Exchange.

  Provides functionality to exchange an existing access token or refresh token
  for a new token with a subset of the original token's scopes.
  """

  alias Hexpm.OAuth.{Clients, Tokens}
  alias Hexpm.Permissions
  alias Hexpm.Repo

  @doc """
  Exchanges a subject token for a new token with target scopes.

  Parameters:
  - client_id: The OAuth client requesting the exchange
  - subject_token: The token being exchanged (access token or refresh token)
  - subject_token_type: Type of the subject token:
    - "urn:ietf:params:oauth:token-type:access_token" for access tokens
    - "urn:ietf:params:oauth:token-type:refresh_token" for refresh tokens
  - target_scopes: List of scopes for the new token (must be subset of subject token scopes)

  Returns:
  - {:ok, new_token} on success
  - {:error, error_type, description} on failure
  """
  def exchange_token(client_id, subject_token, subject_token_type, target_scopes) do
    with {:ok, _client} <- validate_client(client_id),
         {:ok, parent_token} <-
           validate_subject_token(subject_token, subject_token_type, client_id),
         {:ok, validated_scopes} <- validate_target_scopes(parent_token.scopes, target_scopes),
         {:ok, token_changeset} <-
           create_exchange_token(parent_token, client_id, validated_scopes, subject_token) do
      case Repo.insert(token_changeset) do
        {:ok, new_token} ->
          {:ok, new_token}

        {:error, changeset} ->
          {:error, :server_error,
           "Failed to create exchanged token: #{inspect(changeset.errors)}"}
      end
    end
  end

  defp validate_client(client_id) do
    case Clients.get(client_id) do
      nil -> {:error, :invalid_client, "Invalid client"}
      client -> {:ok, client}
    end
  end

  defp validate_subject_token(subject_token, subject_token_type, client_id) do
    case subject_token_type do
      "urn:ietf:params:oauth:token-type:access_token" ->
        lookup_access_token(subject_token, client_id)

      "urn:ietf:params:oauth:token-type:refresh_token" ->
        lookup_refresh_token(subject_token, client_id)

      unsupported_type ->
        {:error, :invalid_request, "Unsupported subject_token_type: #{unsupported_type}"}
    end
  end

  defp lookup_access_token(user_access_token, client_id) do
    case Tokens.lookup(user_access_token, :access, client_id: client_id) do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_found} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :invalid_token} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :token_invalid} ->
        {:error, :invalid_grant, "Subject token expired or revoked"}

      {:error, _} ->
        {:error, :invalid_grant, "Subject token expired or revoked"}
    end
  end

  defp lookup_refresh_token(user_refresh_token, client_id) do
    case Tokens.lookup(user_refresh_token, :refresh, client_id: client_id) do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_found} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :invalid_token} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :token_invalid} ->
        {:error, :invalid_grant, "Subject token expired or revoked"}

      {:error, _} ->
        {:error, :invalid_grant, "Subject token expired or revoked"}
    end
  end

  defp validate_target_scopes(source_scopes, target_scopes) when is_list(target_scopes) do
    case Permissions.validate_scope_subset(source_scopes, target_scopes) do
      :ok -> {:ok, target_scopes}
      {:error, message} -> {:error, :invalid_scope, message}
    end
  end

  defp validate_target_scopes(source_scopes, target_scopes) when is_binary(target_scopes) do
    target_scope_list = String.split(target_scopes, " ", trim: true)
    validate_target_scopes(source_scopes, target_scope_list)
  end

  defp validate_target_scopes(_source_scopes, nil) do
    {:error, :invalid_request, "Missing required parameter: scope"}
  end

  defp create_exchange_token(parent_token, client_id, target_scopes, grant_reference) do
    token_changeset =
      Tokens.create_exchanged_token(parent_token, client_id, target_scopes, grant_reference)

    {:ok, token_changeset}
  end
end
