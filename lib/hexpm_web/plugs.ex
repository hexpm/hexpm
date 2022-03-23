defmodule HexpmWeb.Plugs do
  import Plug.Conn, except: [read_body: 1]

  alias Hexpm.Accounts.Users
  alias HexpmWeb.ControllerHelpers

  # Max filesize: ~10mb
  # Min upload speed: ~10kb/s
  # Read 100kb every 10s
  @read_body_opts [
    length: 10_000_000,
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
    user_id = get_session(conn, "user_id")
    user = user_id && Users.get_by_id(user_id, [:emails, organizations: :repository])
    conn = assign(conn, :current_organization, nil)

    if user do
      assign(conn, :current_user, user)
    else
      assign(conn, :current_user, nil)
    end
  end

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
      {:ok, %{key: key, user: user, organization: organization, email: email, source: source}} ->
        conn
        |> assign(:key, key)
        |> assign(:current_user, user)
        |> assign(:current_organization, organization)
        |> assign(:email, email)
        |> assign(:auth_source, source)

      {:error, :missing} ->
        conn
        |> assign(:key, nil)
        |> assign(:current_user, nil)
        |> assign(:current_organization, nil)
        |> assign(:email, nil)
        |> assign(:auth_source, nil)

      {:error, _} = error ->
        HexpmWeb.AuthHelpers.error(conn, error)
    end
  end
end
