defmodule ExplexWeb.Router.Util do
  import Plug.Connection
  alias ExplexWeb.User

  def to_iso8601(Ecto.DateTime[] = dt) do
    "#{pad(dt.year, 4)}-#{pad(dt.month, 2)}-#{pad(dt.day, 2)}T" <>
    "#{pad(dt.hour, 2)}:#{pad(dt.min, 2)}:#{pad(dt.sec, 2)}Z"
  end

  defp pad(int, padding) do
    str = to_string(int)
    padding = max(padding-byte_size(str), 0)
    do_pad(str, padding)
  end

  defp do_pad(str, 0), do: str
  defp do_pad(str, n), do: do_pad("0" <> str, n-1)

  def send_render(conn, status, body) do
    case conn.assigns[:format] do
      "json" ->
        body = JSON.encode!(body)
        content_type = "application/json; charset=utf-8"
      "elixir" ->
        # TODO: Convert atoms to strings
        body = inspect(body, limit: :infinity, records: false, binaries: :as_strings)
        content_type = "application/vnd.explex+elixir; charset=utf-8"
    end

    conn
    |> put_resp_header("content-type", content_type)
    |> send_resp(status, body)
  end

  def send_resp(conn, status) do
    conn.status(status).state(:set) |> send_resp
  end

  defmacro forward(path, plug, opts \\ []) do
    path = Path.join(path, "*glob")
    quote do
      match unquote(path) do
        conn = var!(conn).path_info(var!(glob))
        unquote(plug).call(conn, unquote(opts))
      end
    end
  end

  defmacro with_authorized(user \\ { :_, [], nil }, opts) do
    quote do
      case ExplexWeb.Router.Util.authorize(var!(conn)) do
        { :ok, unquote(user) } ->
          unquote(Keyword.fetch!(opts, :do))
        :error ->
          ExplexWeb.Router.Util.send_unauthorized(var!(conn))
      end
    end
  end

  def authorize(conn) do
    case conn.req_headers["authorization"] do
      "Basic " <> credentials ->
        case String.split(:base64.decode(credentials), ":", global: false) do
          [username, password] ->
            user = User.get(username)
            if User.auth?(user, password) do
              { :ok, user }
            else
              :error
            end
          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  def send_unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=explex")
    |> send_resp(401, "")
  end

  def send_creation_resp({ :ok, _ }, conn) do
    send_resp(conn, 201, "")
  end

  def send_creation_resp({ :error, errors }, conn) do
    send_validation_failed(conn, errors)
  end

  def send_update_resp({ :ok, _ }, conn) do
    send_resp(conn, 204)
  end

  def send_update_resp({ :error, errors }, conn) do
    send_validation_failed(conn, errors)
  end

  defp send_validation_failed(conn, errors) do
    body = [message: "Validation failed", errors: errors]
    send_resp(conn, 422, JSON.encode!(body))
  end
end
