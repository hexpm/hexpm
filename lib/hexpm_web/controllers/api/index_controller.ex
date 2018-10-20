defmodule HexpmWeb.API.IndexController do
  use HexpmWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
