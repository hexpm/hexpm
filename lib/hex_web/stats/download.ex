defmodule HexWeb.Stats.Download do
  use Ecto.Model

  queryable "downloads" do
    belongs_to :release, HexWeb.Release
    field :downloads, :integer
    field :day, :date
  end

  def create(release, count, date) do
    download = release.downloads.new(downloads: count, day: date)
               |> HexWeb.Repo.insert
    {:ok, download}
  end
end
