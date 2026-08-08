defmodule HexpmWeb.Live.InitAssigns do
  @moduledoc """
  on_mount callback that assigns `:current_user` and `:current_session` from the
  session in the same way the `login/2` plug does for controllers.
  """

  import Phoenix.Component, only: [assign_new: 3]

  alias Hexpm.UserSessions
  alias Hexpm.Accounts.Users

  def session(conn), do: %{"remote_ip" => conn.remote_ip}

  def on_mount(:default, _params, session, socket) do
    {user, user_session} = resolve_user(session)

    socket =
      socket
      |> assign_new(:current_user, fn -> user end)
      |> assign_new(:current_session, fn -> user_session end)
      |> assign_new(:current_organization, fn -> nil end)

    {:cont, socket}
  end

  defp resolve_user(%{"session_token" => token}) when is_binary(token) do
    with {:ok, decoded} <- Base.decode64(token),
         %{user_id: user_id} = user_session when not is_nil(user_id) <-
           UserSessions.get_browser_session_by_token(decoded) do
      {Users.get_by_id(user_id, [:emails, organizations: :repository]), user_session}
    else
      _ -> {nil, nil}
    end
  end

  defp resolve_user(_session), do: {nil, nil}
end
