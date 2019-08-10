defmodule Hexpm.Repository.Installs do
  use Hexpm.Context

  def all() do
    Repo.all(Install.all())
  end
end
