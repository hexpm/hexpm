defmodule HexpmWeb.Plugs.DashboardAuth do
  @moduledoc """
  Basic Auth for liveview dashboard
  """

  import Plug.BasicAuth

  def init(_opts), do: :ok

  def call(conn, _opts) do
    basic_auth(conn,
      username: Application.get_env(:hexpm, :dashboard_user),
      password: Application.get_env(:hexpm, :dashboard_password)
    )
  end
end
