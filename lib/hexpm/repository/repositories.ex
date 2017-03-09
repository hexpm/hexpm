defmodule Hexpm.Repository.Repositories do
  use Hexpm.Web, :context

  def get(name) do
    Repo.get_by(Repository, name: name)
  end
end
