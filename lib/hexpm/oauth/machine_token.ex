defmodule Hexpm.OAuth.MachineToken do
  alias Hexpm.Accounts.Key

  @enforce_keys [:id, :key, :scopes]
  defstruct [:id, :key, :scopes]

  def new(%Key{} = key, scopes) when is_list(scopes) do
    %__MODULE__{id: key.id, key: key, scopes: scopes}
  end
end
