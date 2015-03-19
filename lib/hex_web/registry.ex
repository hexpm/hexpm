defmodule HexWeb.Registry do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo

  schema "registries" do
    field :state, :string
    field :created_at, :datetime
    field :started_at, :datetime
  end

  def create() do
    registry = %HexWeb.Registry{state: "waiting"}
    {:ok, HexWeb.Repo.insert(registry)}
  end

  def set_working(registry) do
    from(r in HexWeb.Registry, where: r.id == ^registry.id)
    |> HexWeb.Repo.update_all(state: "working", started_at: fragment("now()"))
  end

  def set_done(registry) do
    from(r in HexWeb.Registry, where: r.id == ^registry.id)
    |> HexWeb.Repo.update_all(state: "done")
  end

  def latest_started do
    from(r in HexWeb.Registry,
         where: r.state == "working" or r.state == "done",
         order_by: [desc: r.started_at],
         limit: 1,
         select: r.started_at)
    |> HexWeb.Repo.one
  end
end
