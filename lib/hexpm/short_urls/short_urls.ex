defmodule Hexpm.ShortURLs do
  use Hexpm.Context
  alias Hexpm.ShortURLs.ShortURL

  def add(params) do
    params
    |> ShortURL.changeset()
    |> Repo.insert()
  end

  def get_by_short_code(short_code) do
    Repo.one(from(s in ShortURL, where: s.short_code == ^short_code))
  end
end
