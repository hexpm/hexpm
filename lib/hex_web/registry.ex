defmodule HexWeb.Registry do
  use Ecto.Model

  alias Ecto.Adapters.SQL
  require HexWeb.Repo

  schema "registries" do
    field :state, :string
    # TODO: Should be an incrementing counter (sequence)
    field :started_at, Ecto.DateTime
    timestamps updated_at: false
  end

  @insert_query "INSERT INTO registries (state) VALUES ('waiting') RETURNING *"

  def create() do
    # TODO: Workaround while waiting for read_after_writes
    %{rows: [{id, inserted_at, started_at, state}]} =
      SQL.query(HexWeb.Repo, @insert_query, [])

    {:ok, %HexWeb.Registry{
            id: id,
            inserted_at: Ecto.Type.load!(Ecto.DateTime, inserted_at),
            started_at: started_at,
            state: state}}
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
