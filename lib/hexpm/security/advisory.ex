defmodule Hexpm.Security.Advisory do
  use Hexpm.Schema

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release

  @primary_key false
  schema "security_advisories" do
    field :id, :string, primary_key: true
    belongs_to :package, Package
    field :summary, :string
    field :affected, {:array, Hexpm.VersionRequirement}
    field :published_at, :utc_datetime
    field :modified_at, :utc_datetime
    field :details, :map
    many_to_many :affected_releases, Release, join_through: "security_advisory_affected_releases"
  end

  def all(subject)

  def all(%Package{} = package) do
    assoc(package, :security_advisories)
  end

  def all(%Release{} = release) do
    assoc(release, :security_advisories)
  end
end
