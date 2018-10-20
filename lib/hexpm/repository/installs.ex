defmodule Hexpm.Repository.Installs do
  use HexpmWeb, :context

  def all() do
    Repo.all(Install.all())
  end
end
