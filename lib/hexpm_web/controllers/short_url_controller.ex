defmodule HexpmWeb.ShortURLController do
  use HexpmWeb, :controller
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.ShortURL

  def show(conn, %{"short_code" => short_code}) do
    case ShortURLs.get(short_code) do
      nil ->
        not_found(conn)

      %ShortURL{url: url} ->
        conn
        |> put_status(301)
        |> redirect(external: url)
    end
  end
end
