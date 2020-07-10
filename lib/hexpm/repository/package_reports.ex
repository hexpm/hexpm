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

  def accept(report_id, comment) do
    PackageReport.get(report_id)
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "accepted"})
    |> Repo.update()
  end

  def reject(report_id, comment) do
    PackageReport.get(report_id)
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "rejected"})
    |> Repo.update()
  end

  def solve(report_id, comment) do
    PackageReport.get(report_id)
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "solved"})
    |> Repo.update()
  end
end
