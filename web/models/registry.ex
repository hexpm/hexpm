defmodule HexWeb.Registry do
  use HexWeb.Web, :model

  schema "registries" do
    field :state, :string
    field :inserted_at, Ecto.DateTime, read_after_writes: true
    # TODO: Should be an incrementing counter (sequence)
    field :started_at, Ecto.DateTime
  end

  def create do
    %HexWeb.Registry{}
    |> change(state: "waiting")
    |> prepare_changes(&delete_defaults/1)
  end

  def set_working(registry) do
    from(r in Registry,
         where: r.id == ^registry.id,
         update: [set: [state: "working", started_at: fragment("now()")]])
  end

  def set_done(registry) do
    from(r in Registry,
         where: r.id == ^registry.id,
         update: [set: [state: "done"]])
  end

  def latest_started do
    from(r in Registry,
         where: r.state == "working" or r.state == "done",
         order_by: [desc: r.started_at],
         limit: 1,
         select: r.started_at)
  end

  defp delete_defaults(changeset) do
    delete_change(changeset, :inserted_at)
  end
end
