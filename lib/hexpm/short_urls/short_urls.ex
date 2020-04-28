defmodule Hexpm.ShortURLs do
  use Hexpm.Context
  alias Hexpm.ShortURLs.ShortURL

  def add(params) do
    params
    |> ShortURL.changeset()
    |> Repo.insert()
  end

  def get(short_code) do
    Repo.get_by(ShortURL, short_code: short_code)
  end
end
