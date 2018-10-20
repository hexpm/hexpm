defmodule HexpmWeb.InstallController do
  use HexpmWeb, :controller

  def archive(conn, params) do
    user_agent = get_req_header(conn, "user-agent")
    current = params["elixir"] || version_from_user_agent(user_agent)
    all_versions = Installs.all()

    url =
      case Install.latest(all_versions, current) do
        {:ok, _hex, elixir} ->
          "installs/#{elixir}/hex.ez"

        :error ->
          "installs/hex.ez"
      end

    conn
    |> cache([:public, "max-age": 60 * 60], [])
    |> redirect(external: Hexpm.Utils.cdn_url(url))
  end

  defp version_from_user_agent(user_agent) do
    case List.first(user_agent) do
      "Mix/" <> version -> version
      _ -> "1.0.0"
    end
  end
end
