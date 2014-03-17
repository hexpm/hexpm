defmodule HexWeb.API.Util do
  @doc """
  API related utility functions.
  """

  import Plug.Connection
  alias HexWeb.User

  @doc """
  Renders an entity or dict body and sends it with a status code.
  """
  @spec send_render(Plug.Conn.t, non_neg_integer, term) :: Plug.Conn.t
  def send_render(conn, status, body) when is_list(body) do
    # Handle list of entities
    if body != [] && (impl = HexWeb.Render.impl_for(List.first(body))) do
      body = Enum.map(body, &impl.render(&1))
      send_render(conn, status, body)
    else
      case conn.assigns[:format] do
        "json" ->
          body = JSON.encode!(body)
          content_type = "application/json"
        "elixir" ->
          body = HexWeb.Util.safe_serialize_elixir(body)
          content_type = "application/vnd.hex+elixir"
        _ ->
          raise Plug.Parsers.UnsupportedMediaTypeError
      end

      conn
      |> put_resp_header("content-type", content_type)
      |> send_resp(status, body)
    end
  end

  def send_render(conn, status, entity) do
    body = HexWeb.Render.render(entity)
    send_render(conn, status, body)
  end

  @doc """
  Run the given block if a user authorized, otherwise send an
  unauthorized response.
  """
  @spec with_authorized(Keyword.t) :: Macro.t
  @spec with_authorized(Macro.t, Keyword.t) :: Macro.t
  defmacro with_authorized(user \\ { :_, [], nil }, opts) do
    quote do
      case HexWeb.API.Util.authorize(var!(conn)) do
        { :ok, unquote(user) } ->
          unquote(Keyword.fetch!(opts, :do))
        _ ->
          HexWeb.API.Util.send_unauthorized(var!(conn))
      end
    end
  end

  @doc """
  Run the given block if a user authorized as specified user,
  otherwise send an unauthorized response.
  """
  @spec with_authorized_as(Macro.t, Keyword.t) :: Macro.t
  @spec with_authorized_as(Macro.t, Macro.t, Keyword.t) :: Macro.t
  defmacro with_authorized_as(user \\ { :_, [], nil }, as, opts) do
    as = Enum.map(as, fn { key, val } -> { key, { :^, [], [val] } } end)

    quote do
      case HexWeb.API.Util.authorize(var!(conn)) do
        { :ok, HexWeb.User.Entity[unquote_splicing(as)] = unquote(user) } ->
          unquote(Keyword.fetch!(opts, :do))
        _ ->
          HexWeb.API.Util.send_unauthorized(var!(conn))
      end
    end
  end

  # Check if a user is authorized, return `{ :ok, user }` if so,
  # or `:error` if authorization failed
  @doc false
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

  @doc """
  Send an unauthorized response.
  """
  @spec send_unauthorized(Plug.Conn.t) :: Plug.Conn.t
  def send_unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> send_resp(401, "")
  end

  @doc """
  Send a creation response if entity creation was successful,
  otherwise send validation failure response.
  """
  @spec send_creation_resp({ :ok, term } | { :error, term }, Plug.Conn.t, String.t) :: Plug.Conn.t
  def send_creation_resp({ :ok, entity }, conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_render(201, entity)
  end

  def send_creation_resp({ :error, errors }, conn, _location) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity update was successful,
  otherwise send validation failure response.
  """
  @spec send_update_resp({ :ok, term } | { :error, term }, Plug.Conn.t) :: Plug.Conn.t
  def send_update_resp({ :ok, entity }, conn) do
    send_render(conn, 200, entity)
  end

  def send_update_resp({ :error, errors }, conn) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity delete was successful,
  otherwise send validation failure response.
  """
  @spec send_delete_resp(:ok | { :error, term }, Plug.Conn.t) :: Plug.Conn.t
  def send_delete_resp(:ok, conn) do
    send_resp(conn, 204, "")
  end

  def send_delete_resp({ :error, errors }, conn) do
    send_validation_failed(conn, errors)
  end

  def send_validation_failed(conn, errors) do
    body = [message: "Validation failed", errors: errors]
    send_render(conn, 422, body)
  end
end
