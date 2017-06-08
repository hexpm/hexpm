defmodule Hexpm.Web.Plugs do
  import Plug.Conn, except: [read_body: 1]

  # Max filesize: ~10mb
  # Min upload speed: ~10kb/s
  # Read 100kb every 10s
  @read_body_opts [
    length: 10_000_000,
    read_length: 100_000,
    read_timeout: 10_000
  ]

  def fetch_body(conn, _opts) do
    {conn, body} = read_body(conn)
    put_in(conn.params["body"], body)
  end

  def read_body_finally(conn, _opts) do
    register_before_send(conn, fn conn ->
      if conn.status in 200..399 do
        conn
      else
        # If we respond with an unsuccessful error code assume we did not read
        # body. Read the full body to avoid closing the connection too early,
        # works around getting H13/H18 errors on Heroku.
        case read_body(conn, @read_body_opts) do
          {:ok, _body, conn} -> conn
          _ -> conn
        end
      end
    end)
  end

  defp read_body(conn) do
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

  def user_agent(conn, _opts) do
    case get_req_header(conn, "user-agent") do
      [value | _] ->
        assign(conn, :user_agent, value)
      [] ->
        if Application.get_env(:hexpm, :user_agent_req) do
          Hexpm.Web.ControllerHelpers.render_error(conn, 400, message: "User-Agent header is requried")
        else
          assign(conn, :user_agent, "missing")
        end
    end
  end

  def web_user_agent(conn, _opts) do
    assign(conn, :user_agent, "WEB")
  end

  def default_repository(conn, _opts) do
    param_set? = Map.has_key?(conn.params, "repository")

    case conn.path_info do
      ["api", "packages" | _] when not param_set? ->
        put_in(conn.params["repository"], "hexpm")
      ["packages" | _] when not param_set? ->
        put_in(conn.params["repository"], "hexpm")
      _ ->
        conn
    end
  end

  def login(conn, _opts) do
    user_id = get_session(conn, "user_id")

    user = user_id && Hexpm.Accounts.Users.get_by_id(user_id)
    user = user && Hexpm.Accounts.Users.with_emails(user)

    if user do
      assign(conn, :logged_in, user)
    else
      assign(conn, :logged_in, nil)
    end
  end

  def auth_gate(conn, _opts) do
    if possible = Application.get_env(:hexpm, :auth_gate) do
      case get_req_header(conn, "authorization") do
        ["Basic " <> credentials | _] ->
          possible = String.split(possible, ",")
          basic_auth(conn, credentials, possible)
        _ ->
          auth_error(conn)
      end
    else
      conn
    end
  end

  def authenticate(conn, _opts) do
    case Hexpm.Web.AuthHelpers.authenticate(conn) do
      {:ok, {user, key, email}} ->
        conn
        |> assign(:user, user)
        |> assign(:key, key)
        |> assign(:email, email)
      {:error, :missing} ->
        conn
        |> assign(:user, nil)
        |> assign(:key, nil)
        |> assign(:email, nil)
      {:error, _} = error ->
        Hexpm.Web.AuthHelpers.error(conn, error)
    end
  end

  defp basic_auth(conn, credentials, possible) do
    credentials = Base.decode64!(credentials)
    if credentials in possible do
      update_auth_header(conn)
    else
      auth_error(conn)
    end
  end

  # Try to enable use of  multiple auth headers for API
  defp update_auth_header(conn) do
    if authorization = get_req_header(conn, "authorization") |> Enum.at(1) do
      put_req_header(conn, "authorization", authorization)
    else
      %{conn | req_headers: List.keydelete(conn.req_headers, "authorization", 0)}
    end
  end

  defp auth_error(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> Hexpm.Web.ControllerHelpers.render_error(401)
    |> halt
  end
end
