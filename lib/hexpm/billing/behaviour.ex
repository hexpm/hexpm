defmodule Hexpm.Billing.Behaviour do
  @type organization() :: String.t()

  @callback checkout(organization(), data :: map()) :: {:ok, map()} | {:error, map()}
  @callback get(organization()) :: map() | nil
  @callback cancel(organization()) :: map()
  @callback create(map()) :: {:ok, map()} | {:error, map()}
  @callback update(organization(), map()) :: {:ok, map()} | {:error, map()}
  @callback change_plan(organization(), map()) :: :ok
  @callback invoice(id :: pos_integer()) :: binary()
  @callback pay_invoice(id :: pos_integer()) :: :ok | {:error, map()}
  @callback report() :: [map()]
end
