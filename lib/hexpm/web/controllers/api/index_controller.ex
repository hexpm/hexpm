defmodule Hexpm.Web.API.IndexController do
  use Hexpm.Web, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
