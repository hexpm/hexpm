defmodule Hexpm.Repository.PackageReport do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  schema "package_reports" do
    field :state, :string, default: "to_accept"
    field :description, :string

    belongs_to :author, Hexpm.Accounts.User
    belongs_to :package, Package
    #field :requirement, :string
    has_many :affected_releases, AffectedRelease
    has_many :releases, through: [:affected_releases, :release]

    timestamps()
  end

  @valid_states ["to_accept","accepted","rejected","solved"]

  def build(releases, user, package, params) do
    %PackageReport{}
    |> cast(params, ~w(state description)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:description, min: 2, max: 500)
    |> put_assoc(:affected_releases, get_list_of_affected(releases))
    |> put_assoc(:author, user)
    |> put_assoc(:package, package)   
  end

  def change_state(package_report,params) do
    cast(package_report, params, ~w(state)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
  end

  def all(count) do
    from(
      p in PackageReport,
      preload: :affected_releases,
      preload: :author,
      preload: :releases,
      preload: :package,
      select: p
    )
    |>Hexpm.Utils.paginate(1,count)
  end

  def count() do
    from(r in PackageReport, select: count(r.id))
  end

  defp get_list_of_affected(releases) do
    Enum.map(releases, fn r -> %AffectedRelease{release_id: r.id} end)
  end
end
