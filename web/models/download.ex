defmodule HexWeb.Download do
  use HexWeb.Web, :model

  schema "downloads" do
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
  end
end
