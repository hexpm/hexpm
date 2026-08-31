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

  @callback validate_logout_token(Connection.t(), String.t()) ::
              {:ok, map()} | {:error, Error.t()}

  def impl do
    Application.fetch_env!(:hexpm, :organization_sso)
    |> Keyword.fetch!(:oidc_impl)
  end

  @doc """
  Whether the `sub` claim is one we can store and match an identity on.
  """
  def valid_subject?(subject) when is_binary(subject) do
    subject != "" and byte_size(subject) <= 255 and
      subject |> :binary.bin_to_list() |> Enum.all?(&(&1 <= 127))
  end

  def valid_subject?(_subject), do: false

  @doc """
  Whether the `email` claim is one we can store. The claim is optional, so its
  absence is valid.
  """
  def valid_provider_email?(nil), do: true

  def valid_provider_email?(email) when is_binary(email) do
    byte_size(email) <= 320 and String.valid?(email)
  end

  def valid_provider_email?(_email), do: false

  @doc """
  When the cached provider metadata stops being usable, which is as soon as
  either half of it does.
  """
  def metadata_expires_at(discovery_expires_at, jwks_expires_at) do
    if DateTime.compare(discovery_expires_at, jwks_expires_at) == :gt,
      do: jwks_expires_at,
      else: discovery_expires_at
  end
end
