defmodule HexWeb.Registry do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo

  queryable "registries" do
    field :state, :string
    field :created, :datetime
    field :started, :datetime
  end

  def create() do
    registry = HexWeb.Registry.new(state: "waiting")
    { :ok, HexWeb.Repo.create(registry) }
  end

  def set_working(registry) do
    from(r in HexWeb.Registry, where: r.id == ^registry.id)
    |> HexWeb.Repo.update_all(state: "working", started: now())
  end

  def set_done(registry) do
    from(r in HexWeb.Registry, where: r.id == ^registry.id)
    |> HexWeb.Repo.update_all(state: "done")
  end

  def latest_started do
    from(r in HexWeb.Registry,
         where: r.state == "working" or r.state == "done",
         order_by: [desc: r.started],
         limit: 1,
         select: r.started)
    |> HexWeb.Repo.all
    |> List.first
  end
end
