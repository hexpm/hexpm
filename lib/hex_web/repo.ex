defmodule HexWeb.Repo do
  use Ecto.Repo, otp_app: :hex_web

  def refresh_view(schema) do
    source = schema.__schema__(:source)
    
    Ecto.Adapters.SQL.query(
       HexWeb.Repo,
       ~s(REFRESH MATERIALIZED VIEW "#{source}"),
       [])
  end
end
