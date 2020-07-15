defmodule Hexpm.Repository.PackageReportComment do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  schema "comments" do
    field :text, :string
    timestamps()

    belongs_to :report, PackageReport
    belongs_to :author, User
  end

  def build(report, user, params) do
    %Comment{}
    |> cast(params, ~w(text)a)
    |> validate_required(:text)
    |> validate_required(:text, min: 2)
    |> put_assoc(:author, user)
    |> put_assoc(:report, report)
  end

  def all_for_report(report_id) do
    from(
      c in Comment,
      join: r in assoc(c, :report),
      preload: :author,
      where: r.id == ^report_id,
      select: c
    )
  end

  def count(report_id) do
    from(
      c in Comment,
      join: r in assoc(c, :report),
      where: r.id == ^report_id,
      select: count(r.id)
    )
  end
end
