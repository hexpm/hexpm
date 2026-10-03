defmodule HexpmWeb.ShortURLController do
  use HexpmWeb, :controller
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.ShortURL

  def show(conn, %{"short_code" => short_code}) do
    case ShortURLs.get(short_code) do
      nil ->
        not_found(conn)

      short_url ->
        case ShortURL.redirect_url(short_url) do
          nil ->
            not_found(conn)

          url ->
            conn
            |> put_status(301)
            |> redirect(external: url)
        end
    end
  end
end
