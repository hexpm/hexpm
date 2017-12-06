defmodule Hexpm.Billing do
  @type repository() :: String.t()

  @callback dashboard(repository()) :: map()
  @callback invoice(id :: pos_integer()) :: binary()
  @callback checkout(repository(), data :: map()) :: map()

  @billing_impl Application.get_env(:hexpm, :billing_impl)

  defdelegate dashboard(repository), to: @billing_impl
  defdelegate invoice(id), to: @billing_impl
  defdelegate checkout(repository, data), to: @billing_impl
end
