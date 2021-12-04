defmodule HexpmWeb.SearchLive do
  @moduledoc """
  A LiveView for live package search from queries.
  """
  use HexpmWeb, :live_view

  alias Hexpm.Repository.Packages

  require Logger

  @max_matches 5
  @matches_sort :recent_downloads
  @query_size_limit_bytes 100

  @impl true
  def render(assigns) do
    HexpmWeb.PageView.render("search.html", assigns)
  end

  @impl true
  def mount(_params, _session, socket) do
    repositories = Enum.map(Hexpm.Accounts.Users.all_organizations(nil), & &1.repository)

    {:ok,
     assign(socket,
       container: nil,
       custom_flash: true,
       hide_search: true,
       query: nil,
       result: nil,
       loading: false,
       matches: [],
       repositories: repositories
     )}
  end

  @impl true
  def handle_event("suggest", %{"search" => query}, socket)
      when byte_size(query) <= @query_size_limit_bytes do
    Logger.debug("Got suggest event in #{__MODULE__} with query: #{query}")

    results =
      Packages.search(
        socket.assigns.repositories,
        0,
        @max_matches,
        Hexpm.Utils.parse_search(query),
        @matches_sort,
        nil
      )

    {:noreply, assign(socket, matches: results)}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    Logger.debug("Got search event in #{__MODULE__} with query: #{query}")

    {:noreply,
     redirect(
       socket,
       to:
         Routes.package_path(
           socket,
           :index,
           search: query,
           sort: "recent_downloads"
         )
     )}
  end
end
