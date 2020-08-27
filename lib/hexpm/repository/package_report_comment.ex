defmodule Hexpm.Repository.PackageReportComment do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  schema "package_report_comments" do
    field :text, :string
    timestamps()

    belongs_to :package_report, PackageReport
    belongs_to :author, User
  end

  def build(report, user, params) do
    %PackageReportComment{}
    |> cast(params, ~w(text)a)
    |> validate_required(:text)
    |> validate_required(:text, min: 2)
    |> put_assoc(:author, user)
    |> put_assoc(:package_report, report)
  end

  def all_for_report(report_id) do
    from(
      c in PackageReportComment,
      join: r in assoc(c, :package_report),
      preload: :author,
      where: r.id == ^report_id,
      select: c
    )
  end
end
