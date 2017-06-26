defmodule Hexpm.Repository.Repositories do
  use Hexpm.Web, :context

  def all_public() do
    Repo.all(from(r in Repository, where: r.public))
  end

  def all_by_user(user) do
    Repo.all(assoc(user, :repositories))
  end

  def get(name) do
    Repo.get_by(Repository, name: name)
  end

  def access?(repository, nil) do
    repository.public
  end
  def access?(repository, user) do
    repository.public or Repo.one!(Repository.has_access(repository, user))
  end
end
