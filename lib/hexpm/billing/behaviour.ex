defmodule Hexpm.Billing.Behaviour do
  @type organization() :: String.t()

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  @callback checkout(organization(), data :: map()) :: {:ok, map()} | {:error, map()}
  @callback get(organization()) :: map() | nil
  @callback cancel(organization()) :: map()
  @callback resume(organization()) :: {:ok, map()} | {:error, map()}
  @callback create(map()) :: {:ok, map()} | {:error, map()}
  @callback update(organization(), map()) :: {:ok, map()} | {:error, map()}
  @callback change_plan(organization(), map()) :: :ok
  @callback invoice(id :: pos_integer()) :: binary()
  @callback pay_invoice(id :: pos_integer()) :: :ok | {:error, map()}
  @callback report() :: [map()]
  @callback pending_payment_action(organization()) :: map()
end
