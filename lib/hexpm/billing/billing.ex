defmodule Hexpm.Billing do
  use Hexpm.Context

  @type organization() :: String.t()

  @callback checkout(organization(), data :: map()) :: map()
  @callback get(organization()) :: map() | nil
  @callback cancel(organization()) :: map()
  @callback create(map()) :: {:ok, map()} | {:error, map()}
  @callback update(organization(), map()) :: {:ok, map()} | {:error, map()}
  @callback change_plan(organization(), map()) :: :ok
  @callback invoice(id :: pos_integer()) :: binary()
  @callback pay_invoice(id :: pos_integer()) :: :ok | {:error, map()}
  @callback report() :: [map()]

  defp impl(), do: Application.get_env(:hexpm, :billing_impl)

  def checkout(organization, data), do: impl().checkout(organization, data)
  def get(organization), do: impl().get(organization)
  def cancel(organization), do: impl().cancel(organization)
  def create(params), do: impl().create(params)
  def update(organization, params), do: impl().update(organization, params)
  def change_plan(organization, params), do: impl().change_plan(organization, params)
  def invoice(id), do: impl().invoice(id)
  def pay_invoice(id), do: impl().pay_invoice(id)
  def report(), do: impl().report()

  def create(params, audit: %{audit_data: audit_data, organization: organization}) do
    case impl().create(params) do
      {:ok, result} ->
        Repo.insert!(audit(audit_data, "billing.create", {organization, params}))
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
