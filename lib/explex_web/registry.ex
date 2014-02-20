defmodule ExplexWeb.Registry do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]

  queryable "registries" do
    field :version, :integer
    field :data, :binary
    field :created, :datetime
  end

  def create(version, data) do
    registry = ExplexWeb.Registry.new(data: data, version: version)
    { :ok, ExplexWeb.Repo.create(registry) }
  end

  def get(newer_than) do
    from(r in ExplexWeb.Registry,
         where: r.version > ^newer_than,
         order_by: [desc: r.version],
         limit: 1)
    |> ExplexWeb.Repo.all
    |> List.first
  end
end
