defmodule HexpmWeb.DashboardController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    redirect(conn, to: ~p"/dashboard/profile")
  end
end
