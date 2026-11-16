defmodule HexpmWeb.ImpersonationController do
  use HexpmWeb, :controller

  alias Hexpm.UserSessions
  alias HexpmWeb.Plugs.Impersonation

  def stop(%{assigns: %{impersonator: %User{}}} = conn, _params) do
    if Hexpm.Repo.write_mode?() do
      UserSessions.revoke(conn.assigns.current_session)
    end

    conn
    |> delete_session(Impersonation.session_key())
    |> redirect(to: ~p"/dashboard/admin/users/#{conn.assigns.current_user.username}")
  end

  def stop(conn, _params) do
    redirect(conn, to: ~p"/")
  end
end
