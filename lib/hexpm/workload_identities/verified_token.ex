defmodule Hexpm.WorkloadIdentities.VerifiedToken do
  @moduledoc """
  An OIDC token whose signature and standard claims have been verified.
  """

  alias Hexpm.WorkloadIdentities.Provider

  @enforce_keys [:provider, :claims]
  defstruct [:provider, :claims]

  @type t :: %__MODULE__{provider: module(), claims: Provider.claims()}
end
