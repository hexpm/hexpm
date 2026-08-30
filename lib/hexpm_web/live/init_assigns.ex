defmodule HexpmWeb.Live.InitAssigns do
  @moduledoc """
  on_mount callback that assigns `:current_user` and `:current_session` from the
  session in the same way the `login/2` plug does for controllers.

  The mount-time resolution is a snapshot and a connected socket outlives it, so
  the same resolution runs again before every `handle_params` and
  `handle_event`. A session revoked or expired since mount resolves to nobody,
  and a membership removed since mount is absent from the reloaded association.
  An idle socket requests nothing, so refreshing on the events that do bounds
  every authorization input to one event of staleness, the same bound a
  controller gets per request.
  """

  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

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
      |> attach_refresh(session)

    {:cont, socket}
  end

  # The session snapshot is fixed when the socket connects, so a socket that
  # connected without a token can never gain one and needs no refreshing.
  defp attach_refresh(socket, %{"session_token" => _} = session) do
    socket
    |> attach_hook(:refresh_auth_params, :handle_params, fn _params, _uri, socket ->
      {:cont, refresh(socket, session)}
    end)
    |> attach_hook(:refresh_auth_event, :handle_event, fn _event, _params, socket ->
      {:cont, refresh(socket, session)}
    end)
  end

  defp attach_refresh(socket, _session), do: socket

  # The disconnected render's handle_params runs right after mount resolved, so
  # only a connected socket resolves again.
  defp refresh(socket, session) do
    if connected?(socket) do
      {user, user_session} = resolve_user(session)

      socket
      |> assign(:current_user, user)
      |> assign(:current_session, user_session)
    else
      socket
    end
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
