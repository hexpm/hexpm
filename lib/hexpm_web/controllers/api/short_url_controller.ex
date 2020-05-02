defmodule HexpmWeb.API.ShortURLController do
  use HexpmWeb, :controller
  alias Hexpm.ShortURLs

  def create(conn, params) do
    case ShortURLs.add(params) do
      {:ok, short_url} ->
        conn
        |> put_status(201)
        |> render(:show, url: Routes.short_url_url(conn, :show, short_url.short_code))

      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end
end
