defmodule Hexpm.Repository.PackageReports do
  use Hexpm.Context

  def add(params) do
    Repo.insert(
      PackageReport.build(
        params["releases"],
        params["user"],
        params["package"],
        params
      )
    )
  end

  def all() do
    PackageReport.all()
    |> Repo.all()
  end

  def count() do
    PackageReport.count()
    |> Repo.one()
  end

  def get(id) do
    PackageReport.get(id)
    |> Repo.one()
  end

  def accept(report, comment) do
    PackageReport.change_state(report, %{"comment" => comment, "state" => "accepted"})
    |> Repo.update()
  end

  def reject(report, comment) do
    PackageReport.change_state(report, %{"comment" => comment, "state" => "rejected"})
    |> Repo.update()
  end

  def solve(report, comment) do
    PackageReport.change_state(report, %{"comment" => comment, "state" => "solved"})
    |> Repo.update()
  end
end
