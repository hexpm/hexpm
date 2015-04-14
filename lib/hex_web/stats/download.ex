defmodule HexWeb.Stats.Download do
  use Ecto.Model

  schema "downloads" do
    belongs_to :release, HexWeb.Release
    field :downloads, :integer
    field :day, Ecto.Date
  end
end
