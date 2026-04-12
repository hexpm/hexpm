defmodule HexpmWeb.PackageLive.Index do
  use HexpmWeb, :live_view

  alias Hexpm.Repository.Package.SearchQuery

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, title: "Packages", container: "container")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:ok, _query} = SearchQuery.parse(params["search"])
    {:noreply, assign(socket, params: params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <h1 class="text-4xl font-bold">Packages (LiveView scaffold)</h1>
      <p>Params: <code>{inspect(@params)}</code></p>
    </div>
    """
  end
end
