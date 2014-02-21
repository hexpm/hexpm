defmodule HexWeb.Registry do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]

  queryable "registries" do
    field :version, :integer
    field :data, :binary
    field :created, :datetime
  end

  def create(version, data) do
    registry = HexWeb.Registry.new(data: data, version: version)
    { :ok, HexWeb.Repo.create(registry) }
  end

  def get(newer_than) do
    from(r in HexWeb.Registry,
         where: r.version > ^newer_than,
         order_by: [desc: r.version],
         limit: 1)
    |> HexWeb.Repo.all
    |> List.first
  end
end
