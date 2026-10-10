defmodule Hexpm.WorkloadIdentities.Provider do
  @moduledoc """
  Behaviour for workload identity OIDC providers.
  """

  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  @type claims :: map()
  @type immutable_ids :: %{
          required(:repository_owner_id) => String.t() | integer(),
          optional(:repository_id) => String.t() | integer() | nil
        }

  @callback name() :: String.t()
  @callback issuer() :: String.t()
  @callback resolve_immutable_ids(map()) :: {:ok, immutable_ids()} | {:error, term()}
  @callback validate_claims(claims()) :: :ok | {:error, term()}
  @callback rate_limit_key(claims()) :: term()
  @callback match?(WorkloadIdentity.t(), claims()) :: boolean()
  @callback claims_snapshot(claims()) :: map()

  @implementations [Hexpm.WorkloadIdentities.Provider.GitHub]

  def get(name) when is_binary(name), do: Enum.find(@implementations, &(&1.name() == name))

  def get_by_issuer(issuer) when is_binary(issuer),
    do: Enum.find(@implementations, &(&1.issuer() == issuer))

  def known_issuers, do: Enum.map(@implementations, & &1.issuer())
end
