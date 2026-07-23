defmodule Hexpm.Accounts.SSO.OIDC do
  alias Hexpm.Accounts.SSO.{Connection, Error, Transaction}

  @type discovery_result :: %{
          discovery_document: map(),
          jwks_document: map(),
          discovery_expires_at: DateTime.t(),
          jwks_expires_at: DateTime.t(),
          metadata_expires_at: DateTime.t()
        }

  @callback discover(String.t()) :: {:ok, discovery_result()} | {:error, Error.t()}

  @callback authorization_uri(Connection.t(), Transaction.t(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, Error.t()}

  @callback exchange_code(Connection.t(), Transaction.t(), String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, Error.t()}

  def impl do
    Application.fetch_env!(:hexpm, :organization_sso)
    |> Keyword.fetch!(:oidc_impl)
  end
end
