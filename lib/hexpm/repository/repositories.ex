defmodule Hexpm.Repository.Repositories do
  use Hexpm.Context

  def all_public() do
    [Repository.hexpm()]
  end

  def get(name, preload \\ []) do
    Repo.get_by(Repository, name: name)
    |> Repo.preload(preload)
  end
end
