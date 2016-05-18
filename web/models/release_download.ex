defmodule HexWeb.ReleaseDownload do
  use HexWeb.Web, :model

  @primary_key false

  schema "release_downloads" do
    belongs_to :release, Release, references: :id
    field :downloads, :integer
  end

  def release(release) do
    from(rd in ReleaseDownload,
         where: rd.release_id == ^release.id)
  end
end
