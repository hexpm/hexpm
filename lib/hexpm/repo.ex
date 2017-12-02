# Needed to support old hex clients for CI testing
if Mix.env == :hex do
  defmodule HexWeb.Repo do
    use Ecto.Repo, otp_app: :hexpm
  end
end

defmodule Hexpm.Repo do
  use Ecto.Repo, otp_app: :hexpm
  import Ecto.Query

  @advisory_locks %{
    registry: 1
  }

  def init(opts) do
    if url = System.get_env("DATABASE_URL") do
      {:ok, Keyword.put(opts, :url, url)}
    else
      {:ok, opts}
    end
  end

  def refresh_view(schema) do
    source = schema.__schema__(:source)

    {:ok, _} = Ecto.Adapters.SQL.query(
       Hexpm.Repo,
       ~s(REFRESH MATERIALIZED VIEW "#{source}"),
       [])
    :ok
  end

  def transaction_with_isolation(fun_or_multi, opts) do
    false = Hexpm.Repo.in_transaction?
    level = Keyword.fetch!(opts, :level)

    transaction(fn ->
      {:ok, _} = Ecto.Adapters.SQL.query(Hexpm.Repo, "SET TRANSACTION ISOLATION LEVEL #{level}", [])
      transaction(fun_or_multi, opts)
    end, opts)
    |> unwrap_transaction_result
  end

  defp unwrap_transaction_result({:ok, result}), do: result
  defp unwrap_transaction_result(other), do: other

  def advisory_lock(key, opts) do
    {:ok, _} = Ecto.Adapters.SQL.query(
       Hexpm.Repo,
       "SELECT pg_advisory_xact_lock($1)",
       [Map.fetch!(@advisory_locks, key)],
       opts)
    :ok
  end

  def pluck(q, field) when is_atom(field) do
    pluck(q, [field]) |> Enum.map(&List.first/1)
  end
  def pluck(q, fields) when is_list(fields) do
    select(q, [x], map(x, ^fields)) |> all() |> Enum.map(&take_values(&1, fields))
  end

  defp take_values(map, fields) when is_map(map) and is_list(fields) do
    Enum.map(fields, &Map.fetch!(map, &1))
  end
end
