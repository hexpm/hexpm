defmodule HexWeb.Repo do
  use Ecto.Repo, otp_app: :hex_web

  def refresh_view(schema) do
    source = schema.__schema__(:source)

    {:ok, _} = Ecto.Adapters.SQL.query(
       HexWeb.Repo,
       ~s(REFRESH MATERIALIZED VIEW "#{source}"),
       [])
    :ok
  end

  def transaction_isolation(level) do
    false = HexWeb.Repo.in_transaction?

    {:ok, _} = Ecto.Adapters.SQL.query(
       HexWeb.Repo,
       "SET TRANSACTION ISOLATION LEVEL #{level}",
       [])
    :ok
  end

  def transaction_with_isolation(fun_or_multi, opts) do
    false = HexWeb.Repo.in_transaction?
    level = Keyword.fetch!(opts, :level)

    transaction(fn ->
      {:ok, _} = Ecto.Adapters.SQL.query(HexWeb.Repo, "SET TRANSACTION ISOLATION LEVEL #{level}", [])
      transaction(fun_or_multi, opts)
    end, opts)
    |> unwrap_transaction_result
  end

  defp unwrap_transaction_result({:ok, result}), do: result
  defp unwrap_transaction_result(other), do: other
end
