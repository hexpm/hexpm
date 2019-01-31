defmodule HexpmWeb.API.RepositoryView do
  use HexpmWeb, :view

  def render("index." <> _, %{repositories: repositories}),
    do: render_many(repositories, __MODULE__, "show")

  def render("show." <> _, %{repository: repository}),
    do: render_one(repository, __MODULE__, "show")

  def render("show", %{repository: repository}) do
    # TODO: Add url
    # TODO: Add packages

    %{
      name: repository.name,
      inserted_at: repository.inserted_at,
      updated_at: repository.updated_at
    }
  end
end
