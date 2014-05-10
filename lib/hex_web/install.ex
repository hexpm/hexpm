defmodule HexWeb.Install do
  use Ecto.Model

  queryable "installs" do
    field :hex, :string
    field :elixir, :string
  end

  def all do
    HexWeb.Repo.all(HexWeb.Install)
  end
end
