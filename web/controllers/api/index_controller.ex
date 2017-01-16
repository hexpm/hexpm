defmodule HexWeb.API.IndexController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
