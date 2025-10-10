defmodule HexpmWeb.Plugs do
  import Plug.Conn, except: [read_body: 1]

  alias Hexpm.Accounts.Users
  alias HexpmWeb.ControllerHelpers

  # Max filesize: 20mib
  # Min upload speed: ~10kb/s
  # Read 100kb every 10s
  @read_body_opts [
    length: 20 * 1024 * 1024,
    read_length: 100_000,
    read_timeout: 10_000
  ]

  def validate_url(conn, _opts) do
    if String.contains?(conn.request_path <> conn.query_string, "%00") do
      conn
      |> ControllerHelpers.render_error(400)
      |> halt()
    else
      conn
    end
  end

  def fetch_body(conn, _opts) do
    # Skip body reading if client sent Expect: 100-continue
    # Body will be read after validation in handle_100_continue
    case get_req_header(conn, "expect") do
      ["100-continue"] ->
        conn

      _ ->
        {conn, body} = read_body(conn)
        put_in(conn.params["body"], body)
    end
  end

  def read_body(conn) do
    case read_body(conn, @read_body_opts) do
      {:ok, body, conn} ->
        {conn, body}

      {:error, :timeout} ->
        raise Plug.TimeoutError

      {:error, _} ->
        raise Plug.BadRequestError

      {:more, _, _} ->
        raise Plug.Parsers.RequestTooLargeError
    end
  end

  def user_agent(conn, opts) do
    case get_req_header(conn, "user-agent") do
      [value | _] ->
        assign(conn, :user_agent, value)

      [] ->
        if Keyword.get(opts, :required, true) && Application.get_env(:hexpm, :user_agent_req) do
          ControllerHelpers.render_error(conn, 400, message: "User-Agent header is required")
        else
          assign(conn, :user_agent, "missing")
        end
    end
  end

  def default_repository(conn, _opts) do
    param_set? = Map.has_key?(conn.params, "repository")

    case conn.path_info do
      ["api", "packages"] -> conn
      ["api", "publish"] when not param_set? -> put_in(conn.params["repository"], "hexpm")
      ["api", "packages" | _] when not param_set? -> put_in(conn.params["repository"], "hexpm")
      ["packages" | _] when not param_set? -> put_in(conn.params["repository"], "hexpm")
      _ -> conn
    end
  end

  def login(conn, _opts) do
    alias Hexpm.UserSessions

    conn = assign(conn, :current_organization, nil)

    session_token = get_session(conn, "session_token")

    user =
      if session_token do
        case Base.decode64(session_token) do
          {:ok, decoded_token} ->
            case UserSessions.get_browser_session_by_token(decoded_token) do
              nil ->
                nil

              session ->
                # Update last_use for browser sessions
                usage_info = %{
                  ip: parse_ip(conn.remote_ip),
                  used_at: DateTime.utc_now(),
                  user_agent: parse_user_agent(get_req_header(conn, "user-agent"))
                }

                UserSessions.update_last_use(session, usage_info)
                Users.get_by_id(session.user_id, [:emails, organizations: :repository])
            end

          _ ->
            nil
        end
      else
        nil
      end

    assign(conn, :current_user, user)
  end

  defp parse_ip(nil), do: nil

  defp parse_ip(ip_tuple) do
    ip_tuple
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp parse_user_agent([]), do: nil
  defp parse_user_agent([value | _]), do: value
  defp parse_user_agent(nil), do: nil

  def disable_deactivated(conn, _opts) do
    if conn.assigns.current_user && conn.assigns.current_user.deactivated_at do
      conn
      |> ControllerHelpers.render_error(400)
      |> halt()
    else
      conn
    end
  end

  def authenticate(conn, _opts) do
    case HexpmWeb.AuthHelpers.authenticate(conn) do
      {:ok,
       %{
         auth_credential: auth_credential,
         user: user,
         organization: organization,
         email: email
       }} ->
        conn
        |> assign(:auth_credential, auth_credential)
        |> assign(:current_user, user)
        |> assign(:current_organization, organization)
        |> assign(:email, email)

      {:error, :missing} ->
        conn
        |> assign(:auth_credential, nil)
        |> assign(:current_user, nil)
        |> assign(:current_organization, nil)
        |> assign(:email, nil)

      {:error, _} = error ->
        HexpmWeb.AuthHelpers.error(conn, error)
    end
  end
end
