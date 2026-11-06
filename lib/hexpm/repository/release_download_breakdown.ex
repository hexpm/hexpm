defmodule Hexpm.Repository.ReleaseDownloadBreakdown do
  use Hexpm.Schema

  @primary_key false

  schema "release_download_breakdowns" do
    belongs_to :package, Package, references: :id
    belongs_to :release, Release, references: :id
    field :view, :string
    field :downloads, :integer
  end
end
