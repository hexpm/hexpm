defmodule Hexpm.Repository.Installs do
  use Hexpm.Web, :context

  def all() do
    Repo.all(Install.all)
  end
end
