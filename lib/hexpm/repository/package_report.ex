defmodule Hexpm.Repository.PackageReport do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  schema "package_reports" do
    field :state, :string, default: "to_accept"
    field :description, :string

    belongs_to :author, Hexpm.Accounts.User
    belongs_to :package, Package
    field :requirement, :string
    has_many :releases, Release

    timestamps()
  end

  @valid_states ["to_accept","accepted","rejected","solved"]

  def build(release, user, params) do
    package_report =
      build_assoc(release, :package_reports)
      |> Map.put(:release, release)
      |> put_assoc(:author, user)

    package_report
    |> cast(params, ~w(state description)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:description, min: 100, max: 500)    
  end

  def update(package_report,params) do
    cast(package_report, params, ~w(state)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
  end

  def all(count) do
    from(
      r in PackageReport,
      select: r
    )
    |>Hexpm.Utils.paginate(1,count)
  end

  def count() do
    from(r in PackageReport, select: count(r.id))
  end
end
