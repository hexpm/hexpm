defmodule HexpmWeb.Dashboard.AuditLogController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
  end
end
