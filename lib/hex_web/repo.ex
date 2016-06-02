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
    {:ok, _} = Ecto.Adapters.SQL.query(
       HexWeb.Repo,
       "SET TRANSACTION ISOLATION LEVEL #{level}",
       [])
    :ok
  end
end
