defmodule ExplexWeb.Router.Util do
  import Plug.Connection
  alias ExplexWeb.User

  def send_render(conn, status, entity) do
    body = ExplexWeb.Render.render(entity)

    case conn.assigns[:format] do
      "json" ->
        body = JSON.encode!(body)
        content_type = "application/json; charset=utf-8"
      "elixir" ->
        body = safe_serialize_elixir(body)
        content_type = "application/vnd.explex+elixir; charset=utf-8"
    end

    conn
    |> put_resp_header("content-type", content_type)
    |> send_resp(status, body)
  end

  def safe_serialize_elixir(term) do
    binarify(term)
    |> inspect(limit: :infinity, records: false, binaries: :as_strings)
  end

  defp binarify(binary) when is_binary(binary),
    do: binary
  defp binarify(atom) when is_atom(atom),
    do: atom_to_binary(atom)
  defp binarify(list) when is_list(list),
    do: lc(elem inlist list, do: binarify(elem))
  defp binarify({ left, right }),
    do: { binarify(left), binarify(right) }

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

  def send_creation_resp({ :ok, entity }, conn) do
    send_render(conn, 201, entity)
  end

  def send_creation_resp({ :error, errors }, conn) do
    send_validation_failed(conn, errors)
  end

  def send_update_resp({ :ok, entity }, conn) do
    send_render(conn, 204, entity)
  end

  def send_update_resp({ :error, errors }, conn) do
    send_validation_failed(conn, errors)
  end

  defp send_validation_failed(conn, errors) do
    body = [message: "Validation failed", errors: errors]
    send_resp(conn, 422, JSON.encode!(body))
  end
end
