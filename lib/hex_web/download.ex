defmodule HexWeb.Download do
  use Ecto.Model

  queryable "downloads" do
    belongs_to :release, HexWeb.Release
    field :downloads, :integer
    field :day, :date
  end
end
