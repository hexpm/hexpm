defmodule Hexpm.TrustedPublishers.Provider do
  @moduledoc """
  Behaviour for trusted publisher OIDC providers.
  """

  alias Hexpm.TrustedPublishers.TrustedPublisher

  @type claims :: map()
  @type immutable_ids :: %{
          required(:repository_owner_id) => String.t() | integer(),
          optional(:repository_id) => String.t() | integer() | nil
        }

  @callback name() :: String.t()
  @callback issuer() :: String.t()
  @callback required_claims() :: [atom()]
  @callback supported_claims() :: [atom()]
  @callback resolve_immutable_ids(map()) :: {:ok, immutable_ids()} | {:error, term()}
  @callback match?(TrustedPublisher.t(), claims()) :: boolean()

  @providers %{
    "github" => Hexpm.TrustedPublishers.Provider.GitHub
  }

  @issuers %{
    "https://token.actions.githubusercontent.com" => Hexpm.TrustedPublishers.Provider.GitHub
  }

  def get(name) when is_binary(name), do: Map.get(@providers, name)

  def get_by_issuer(issuer) when is_binary(issuer), do: Map.get(@issuers, issuer)

  def known_issuers, do: Map.keys(@issuers)

  def known_providers, do: Map.keys(@providers)
end
