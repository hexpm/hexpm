defmodule HexWeb.API.Util do
  @doc """
  API related utility functions.
  """

  import Plug.Connection
  alias HexWeb.User
  alias HexWeb.API.Key

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
  Run the given block if a user authorized with basic authentication,
  otherwise send an unauthorized response.
  """
  @spec with_authorized_basic(Macro.t, Keyword.t) :: Macro.t
  @spec with_authorized_basic(Macro.t, Keyword.t, Keyword.t) :: Macro.t
  defmacro with_authorized_basic(user, as \\ [], opts) do
    do_with_authorized(user, as, [only_basic: true], Keyword.fetch!(opts, :do))
  end

  @doc """
  Run the given block if a user authorized as specified user,
  otherwise send an unauthorized response.
  """
  @spec with_authorized(Macro.t, Keyword.t) :: Macro.t
  @spec with_authorized(Macro.t, Macro.t, Keyword.t) :: Macro.t
  defmacro with_authorized(user, as \\ [], opts) do
    do_with_authorized(user, as, [], Keyword.fetch!(opts, :do))
  end

  defp do_with_authorized(user, as, opts, block) do
    as = Enum.map(as, fn { key, val } -> { key, { :^, [], [val] } } end)

    quote do
      case HexWeb.API.Util.authorize(var!(conn), unquote(opts)) do
        { :ok, HexWeb.User.Entity[unquote_splicing(as)] = unquote(user) } ->
          unquote(block)
        _ ->
          HexWeb.API.Util.send_unauthorized(var!(conn))
      end
    end
  end

  # Check if a user is authorized, return `{ :ok, user }` if so,
  # or `:error` if authorization failed
  @doc false
  def authorize(conn, opts) do
    only_basic = !!opts[:only_basic]
    case conn.req_headers["authorization"] do
      "Basic " <> credentials ->
        basic_auth(credentials)
      key when not only_basic ->
        key_auth(key)
      _ ->
        :error
    end
  end

  defp basic_auth(credentials) do
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
  end

  defp key_auth(key) do
    case Key.auth(key) do
      nil  -> :error
      user -> { :ok, user }
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
  @spec send_creation_resp(Plug.Conn.t, { :ok, term } | { :error, term }, String.t) :: Plug.Conn.t
  def send_creation_resp(conn, { :ok, entity }, location) do
    conn
    |> put_resp_header("location", location)
    |> send_render(201, entity)
  end

  def send_creation_resp(conn, { :error, errors }, _location) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity update was successful,
  otherwise send validation failure response.
  """
  @spec send_update_resp(Plug.Conn.t, { :ok, term } | { :error, term }) :: Plug.Conn.t
  def send_update_resp(conn, { :ok, entity }) do
    send_render(conn, 200, entity)
  end

  def send_update_resp(conn, { :error, errors }) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity delete was successful,
  otherwise send validation failure response.
  """
  @spec send_delete_resp(Plug.Conn.t, :ok | { :error, term }) :: Plug.Conn.t
  def send_delete_resp(conn, :ok) do
    send_resp(conn, 204, "")
  end

  def send_delete_resp(conn, { :error, errors }) do
    send_validation_failed(conn, errors)
  end

  def send_validation_failed(conn, errors) do
    body = [message: "Validation failed", errors: errors]
    send_render(conn, 422, body)
  end
end
