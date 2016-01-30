defmodule HexWeb.InstallerController do
  use HexWeb.Web, :controller

  def get_archive(conn, params) do
    current = params["elixir"] ||
      case List.first get_req_header(conn, "user-agent") do
        "Mix/" <> version ->
          version
        _ ->
          "1.0.0"
      end

    all_versions = HexWeb.Install.all |> HexWeb.Repo.all

    url =
      case HexWeb.Install.latest(all_versions, current) do
        {:ok, _hex, elixir} ->
          "installs/#{elixir}/hex.ez"
        :error ->
          "installs/hex.ez"
      end

    conn
    |> cache([:public, "max-age": 60*60], [])
    |> redirect(external: HexWeb.Utils.cdn_url(url))
  end
end
