defmodule Hexpm.Repository.Comments do
  use Hexpm.Context

  def new(params) do
    Comment.build(params["report"], params["author"], params)
    |> Repo.insert()
  end

  def count(report_id) do
    Comment.count(report_id)
    |> Repo.one()
  end

  def all_for_report(report_id) do
    Comment.all_for_report(report_id)
    |> Repo.all()
  end
end
