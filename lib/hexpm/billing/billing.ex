defmodule Hexpm.Billing do
  @type repository() :: String.t()

  @callback checkout(repository(), data :: map()) :: map()
  @callback dashboard(repository()) :: map()
  @callback cancel(repository()) :: map()
  @callback create(map()) :: {:ok, map()} | {:error, map()}
  @callback update(repository(), map()) :: {:ok, map()} | {:error, map()}
  @callback invoice(id :: pos_integer()) :: binary()
  @callback report() :: [map()]

  @billing_impl Application.get_env(:hexpm, :billing_impl)

  defdelegate checkout(repository, data), to: @billing_impl
  defdelegate dashboard(repository), to: @billing_impl
  defdelegate cancel(repository), to: @billing_impl
  defdelegate create(params), to: @billing_impl
  defdelegate update(repository, params), to: @billing_impl
  defdelegate invoice(id), to: @billing_impl
  defdelegate report(), to: @billing_impl
end
