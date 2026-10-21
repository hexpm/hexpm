defmodule Hexpm.WorkloadIdentities.Provider do
  @moduledoc """
  Behaviour for workload identity OIDC providers.
  """

  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  @type claims :: map()
  @type repository_ids :: %{
          required(:id) => String.t() | integer() | nil,
          required(:public) => boolean(),
          optional(:moved) => boolean()
        }

  @type immutable_ids :: %{
          required(:repository_owner_id) => String.t() | integer(),
          required(:repositories) => %{String.t() => repository_ids()}
        }

  @callback name() :: String.t()
  @callback issuer() :: String.t()

  @doc """
  Reads the immutable IDs of `:repository_owner` and of each of
  `:repositories`, named `owner/name`. A repository Hex can't see resolves
  to a nil ID, and one that was renamed or transferred is marked `:moved`.
  An owner ID in `:repository_owner_id` is used when Hex sees none of the
  repositories.
  """
  @callback resolve_immutable_ids(%{
              required(:repository_owner) => String.t(),
              required(:repositories) => [String.t()],
              optional(:repository_owner_id) => String.t() | nil
            }) ::
              {:ok, immutable_ids()} | {:error, term()}
  @callback validate_claims(claims()) :: :ok | {:error, term()}
  @callback rate_limit_key(claims()) :: term()
  @callback match?(WorkloadIdentity.t(), claims()) :: boolean()
  @callback claims_snapshot(claims()) :: map()

  @implementations [Hexpm.WorkloadIdentities.Provider.GitHub]

  def get(name) when is_binary(name), do: Enum.find(@implementations, &(&1.name() == name))

  def get_by_issuer(issuer) when is_binary(issuer),
    do: Enum.find(@implementations, &(&1.issuer() == issuer))

  def known_issuers, do: Enum.map(@implementations, & &1.issuer())

  def names, do: Enum.map(@implementations, & &1.name())
end
