defmodule Hexpm.Accounts.SSO.Error do
  defexception [:stage, :code, details: %{}]

  @type t :: %__MODULE__{}

  @impl Exception
  def message(%__MODULE__{stage: stage, code: code}) do
    "organization SSO #{stage} failed with #{code}"
  end
end
