defmodule Hexpm.Repository.Download do
  use Hexpm.Web, :schema

  schema "downloads" do
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
  end
end
