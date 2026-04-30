defmodule Hexpm.Security.Advisory do
  use Hexpm.Schema

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release
  alias Hexpm.Security.AdvisoryAffectedVersion
  alias Hexpm.Security.AdvisoryReference

  @derive {HexpmWeb.Stale, etag: [:__struct__, :id, :modified_at], last_modified: :modified_at}

  @primary_key {:id, :string, autogenerate: false}
  schema "security_advisories" do
    field :summary, :string
    field :aliases, {:array, :string}, default: []
    field :published_at, :utc_datetime
    field :modified_at, :utc_datetime
    field :withdrawn_at, :utc_datetime
    field :cvss_vector, :string
    field :cvss_score, :float
    field :cvss_rating, :string

    has_many :references, AdvisoryReference, on_replace: :delete
    has_many :affected_versions, AdvisoryAffectedVersion, on_replace: :delete

    many_to_many :affected_packages, Package,
      join_through: "security_advisory_affected_packages",
      on_replace: :delete

    many_to_many :affected_releases, Release,
      join_through: "security_advisory_affected_releases",
      on_replace: :delete
  end

  @ratings ~w(none low medium high critical)

  def changeset(advisory, params) do
    advisory
    |> cast(params, ~w(id summary aliases published_at modified_at withdrawn_at
                       cvss_vector cvss_score cvss_rating)a)
    |> validate_required(~w(id summary published_at modified_at)a)
    |> validate_inclusion(:cvss_rating, @ratings)
    |> cast_assoc(:references, with: &AdvisoryReference.changeset/2)
    |> cast_assoc(:affected_versions, with: &AdvisoryAffectedVersion.changeset/2)
    |> unique_constraint(:id, name: "security_advisories_pkey")
  end

  def all(subject)

  def all(%Package{} = package) do
    assoc(package, :security_advisories)
  end

  def all(%Release{} = release) do
    assoc(release, :security_advisories)
  end
end
