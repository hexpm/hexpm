defmodule Hexpm.Repository.PackageReport do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  schema "package_reports" do
    field :state, :string, default: "to_accept"
    field :description, :string

    belongs_to :author, Hexpm.Accounts.User
    belongs_to :package, Package
    #field :requirement, :string
    has_many :package_report_releases, PackageReportRelease
    has_many :releases, through: [:package_report_releases, :release]

    timestamps()
  end

  @valid_states ["to_accept","accepted","rejected","solved"]

  def build(releases, user, package, params) do
    %PackageReport{}
    |> cast(params, ~w(state description)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:description, min: 2, max: 500)
    |> put_assoc(:package_report_releases, get_list_of_affected(releases))
    |> put_assoc(:author, user)
    |> put_assoc(:package, package)   
  end

  def change_state(report, params) do
    cast(report, params, ~w(state)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
  end

  def get(id) do
    from(
      r in PackageReport,
      preload: :author,
      preload: :package,
      preload: :releases,
      preload: :package_report_releases,
      where: r.id == ^id,
      select: r
    )
  end

  def all() do
    from(
      p in PackageReport,
      preload: :package_report_releases,
      preload: :author,
      preload: :releases,
      preload: :package,
      order_by: [desc: p.updated_at]
    )
    |>fields()
    
  end

  def count() do
    from(r in PackageReport, select: count(r.id))
  end

  defp get_list_of_affected(releases) do
    Enum.map(releases, fn r -> %PackageReportRelease{release_id: r.id} end)
  end

  defp fields(query) do
    from(p in query, select: p)
  end
end
