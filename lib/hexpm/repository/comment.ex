defmodule Hexpm.Repository.Comment do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  plug :requires_login

  schema "comments" do
    field :text, :string
    timestamps()

    belongs_to :report, PackageReport
    belongs_to :author, User
    belongs_to :parent, Comment
  end

  def build(report, parent, user, params) do
    %Comment{}
    |> cast(params, ~w(text)a)
    |> validate_required(:text)
    |> validate_required(:text, min: 2)
    |> put_assoc(:parent, parent)
    |> put_assoc(:author, user)
    |> put_assoc(:package_report, report)
  end

  def all_for_report(report_id) do
    from(
      c in Comment,
      preload: author,
      preload: report,
      preload: parent,
      where: c.report.id == report_id and c.parent == nil,
      select: c
    )
  end

  def all_for_comment(comment_id) do
    from(
      c in Comment,
      preload: author,
      preload: parent,
      where: c.parent.id == comment_id,
      select: c
    )
  end

  def count(report_id) do
    from(
      c in Comment,
      preload: parent,
      preload: report,
      where: c.report.id == report_id and c.parent == nil,
      select: count(c)
    )
  end
end
