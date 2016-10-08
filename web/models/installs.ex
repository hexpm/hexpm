defmodule HexWeb.Installs do
  use HexWeb.Web, :crud

  def all do
    Repo.all(Install.all)
  end
end
