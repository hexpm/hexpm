defmodule HexpmWeb.PackageSearchController do
  use HexpmWeb, :controller

  alias Hexpm.Repository.PackageSearches

  plug :requires_login

  def download(conn, _params) do
    package_searches = PackageSearches.all()
    # turn the list of package_searches into a csv format
    contents =
      Enum.reduce(package_searches, "", fn package_search, acc ->
        acc <> "#{package_search.term}, #{package_search.frequency}\n"
      end)

    send_download(conn, {:binary, contents}, filename: "package_searches.csv")
  end
end
