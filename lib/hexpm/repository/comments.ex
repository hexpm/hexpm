defmodule Hexpm.Repository.Packages do
  use Hexpm.Context

  def new(params) do
    Comment.build(params["author"], params["author"], params["parent"], params)
    |> Repo.insert()
  end

  def count(report_id) do
    Comments.count(report_id)
    |> Repo.one()
  end

  def all_for_report(report_id) do
    Comments.all_for_repo(report_id)
    |> Repo.all()
  end

  def all_for_comment(comment_id) do
    Comments.all_for_comment(comment_id)
    |> Repo.all()
  end
end
