defmodule HexWeb.Download do
  use HexWeb.Web, :schema

  schema "downloads" do
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
  end
end
