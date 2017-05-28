defmodule Hexpm.Web.API.RepositoryView do
  use Hexpm.Web, :view

  def render("index." <> _, %{repositories: repositories}),
    do: render_many(repositories, __MODULE__, "repository/index")
  def render("show." <> _, %{repository: repository}),
    do: render_one(repository, __MODULE__, "repository/show")

  def render("repository/" <> _view, %{repository: repository}) do
    Map.take(repository, [:name, :public, :inserted_at, :updated_at])
  end
end
