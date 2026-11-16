defmodule HexpmWeb.Plugs.Impersonation do
  @moduledoc """
  A moderator logged in as another user.

  The moderator's own browser session stays in `"session_token"` and the
  user's session goes in `"impersonation_token"`. The `login/2` plug and
  `HexpmWeb.Live.InitAssigns` resolve the user's session only alongside a
  session of the moderator who started it, while that account still has the
  mod role, so ending the moderator's session or role ends the impersonation.
  The session expires after an hour, after which requests are the moderator's
  again.

  The plug refuses every request that would change something: any method other
  than GET and HEAD, the GET routes that write or finish a login, and the
  recovery codes page. Ending the impersonation and logging out are allowed.
  `HexpmWeb.Plugs.Sudo` lets GET requests through without asking for the user's
  password.
  """

  alias Hexpm.Accounts.{User, Users}
  alias Hexpm.UserSessions
  alias HexpmWeb.ControllerHelpers

  @session_key "impersonation_token"
  @safe_methods ~w(GET HEAD)
  @allowed_routes [{"POST", ["impersonation", "stop"]}, {"POST", ["logout"]}]
  @auth_flows ~w(login logout tfa signup password email auth sso invites sudo oauth)

  def session_key(), do: @session_key

  @doc """
  The user and their impersonation session from a Plug or LiveView session
  map, when `impersonator` started it.
  """
  def resolve(session, %User{} = impersonator) do
    with true <- User.has_role?(impersonator, "mod"),
         token when is_binary(token) <- session[@session_key],
         {:ok, decoded} <- Base.decode64(token),
         %{user_id: user_id} = user_session <-
           UserSessions.get_impersonation_session(decoded, impersonator),
         %User{deactivated_at: nil} = user <-
           Users.get_by_id(user_id, [:emails, organizations: :repository]) do
      {user, user_session}
    else
      _ -> nil
    end
  end

  def resolve(_session, nil), do: nil

  def init(opts), do: opts

  def call(%{assigns: %{impersonator: %User{}}} = conn, _opts) do
    if allowed?(conn), do: conn, else: refuse(conn)
  end

  def call(conn, _opts), do: conn

  def refuse(conn) do
    ControllerHelpers.render_error(conn, 403, message: message(conn.assigns.current_user))
  end

  def message(%User{username: username}),
    do: "This is a read-only admin session as #{username}."

  # The router matches each segment decoded, so /%6Cogin is the /login route.
  defp allowed?(conn) do
    path_info = Enum.map(conn.path_info, &URI.decode/1)

    if conn.method in @safe_methods do
      not blocked_read?(path_info)
    else
      {conn.method, path_info} in @allowed_routes
    end
  end

  defp blocked_read?([segment | _rest]) when segment in @auth_flows, do: true
  defp blocked_read?(["organizations", "authorize"]), do: true
  defp blocked_read?(["organizations", _organization, "authenticate"]), do: true
  defp blocked_read?(["dashboard", "security", "recovery-codes"]), do: true
  defp blocked_read?(_path_info), do: false
end
