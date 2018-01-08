defmodule Hexpm.Billing do
  @type repository() :: String.t()

  @callback checkout(repository(), data :: map()) :: map()
  @callback dashboard(repository()) :: map() | nil
  @callback cancel(repository()) :: map()
  @callback create(map()) :: {:ok, map()} | {:error, map()}
  @callback update(repository(), map()) :: {:ok, map()} | {:error, map()}
  @callback invoice(id :: pos_integer()) :: binary()
  @callback report() :: [map()]

  defp impl(), do: Application.get_env(:hexpm, :billing_impl)

  def checkout(repository, data), do: impl().checkout(repository, data)
  def dashboard(repository), do: impl().dashboard(repository)
  def cancel(repository), do: impl().cancel(repository)
  def create(params), do: impl().create(params)
  def update(repository, params), do: impl().update(repository, params)
  def invoice(id), do: impl().invoice(id)
  def report(), do: impl().report()
end
