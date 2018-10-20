defmodule Hexpm.Repository.Download do
  use HexpmWeb, :schema

  @derive HexpmWeb.Stale

  schema "downloads" do
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
    field :updated_at, :utc_datetime_usec, virtual: true
  end
end
