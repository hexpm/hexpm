defmodule HexWeb.API.Util do
  @doc """
  API related utility functions.
  """

  import Plug.Conn
  alias HexWeb.User
  alias HexWeb.API.Key

  @max_age 60

  defmacro when_stale(entities, opts) do
    quote do
      entities = unquote(entities)
      etag     = HexWeb.Util.etag(entities)
      modified = if is_record(entities), do: Ecto.DateTime.to_erl(entities.updated_at)

      var!(conn) = put_resp_header(var!(conn), "etag", etag)

      if modified do
        var!(conn) = put_resp_header(var!(conn), "last-modified", :cowboy_clock.rfc1123(modified))
      end

      unless HexWeb.API.Util.fresh?(var!(conn), etag: etag, modified: modified) do
        unquote(opts[:do])
      else
        send_resp(var!(conn), 304, "")
      end
    end
  end

  def fresh?(conn, opts) do
    modified_since = List.first get_req_header(conn, "if-modified-since")
    none_match     = List.first get_req_header(conn, "if-none-match")

    if modified_since || none_match do
      success = true

      if modified_since do
        success = not_modified?(modified_since, opts[:modified])
      end
      if success && none_match do
        success = etag_matches?(none_match, opts[:etag])
      end

      success
    end
  end

  defp not_modified?(_modified_since, nil), do: false
  defp not_modified?(modified_since, last_modified) do
    modified_since = :cowboy_http.rfc1123_date(modified_since)
    modified_since = :calendar.datetime_to_gregorian_seconds(modified_since)
    last_modified  = :calendar.datetime_to_gregorian_seconds(last_modified)
    last_modified < modified_since
  end

  defp etag_matches?(_none_match, nil), do: false
  defp etag_matches?(none_match, etag) do
    Plug.Util.list(none_match)
    |> Enum.any?(&(&1 in [etag, "*"]))
  end

  defp cache_entity(conn, entity) do
    etag     = HexWeb.Util.etag(entity)
    modified = Ecto.DateTime.to_erl(entity.updated_at)

    conn
    |> put_resp_header("etag", etag)
    |> put_resp_header("last-modified", :cowboy_clock.rfc1123(modified))
  end

  @doc """
  Renders an entity or dict body and sends it with a status code.
  """
  @spec send_render(Plug.Conn.t, non_neg_integer, term) :: Plug.Conn.t
  @spec send_render(Plug.Conn.t, non_neg_integer, term, boolean) :: Plug.Conn.t
  def send_render(conn, status, body, fallback \\ false)

  def send_render(conn, status, body, fallback) do
    body = render(body)
    send_body(conn, status, body, fallback)
  end

  defp render(list) when is_list(list) do
    Enum.map(list, &HexWeb.Render.render/1)
  end

  defp render(map) when is_map(map) do
    map
  end

  defp render(entity) do
    HexWeb.Render.render(entity)
  end

  defp send_body(conn, status, body, fallback) do
    case conn.assigns[:format] do
      :elixir ->
        body = HexWeb.Util.safe_serialize_elixir(body)
        content_type = "application/vnd.hex+elixir"
      format when format == :json or fallback ->
        body = HexWeb.Util.json_encode(body)
        content_type = "application/json"
      _ ->
        raise Plug.Parsers.UnsupportedMediaTypeError
    end

    conn
    |> put_resp_header("content-type", content_type)
    |> send_resp(status, body)
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
    case get_req_header(conn, "authorization") do
      ["Basic " <> credentials] ->
        basic_auth(credentials)
      [key] when not only_basic ->
        key_auth(key)
      _ ->
        :error
    end
  end

  defp basic_auth(credentials) do
    case String.split(:base64.decode(credentials), ":", parts: 2) do
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
  @spec send_creation_resp(Plug.Conn.t, { :ok, term } | { :error, term }, :public | :private, String.t) :: Plug.Conn.t
  def send_creation_resp(conn, { :ok, entity }, privacy, location) do
    conn
    |> put_resp_header("location", location)
    |> cache_entity(entity)
    |> cache(privacy)
    |> send_render(201, entity)
  end

  def send_creation_resp(conn, { :error, errors }, _privacy, _location) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity update was successful,
  otherwise send validation failure response.
  """
  @spec send_update_resp(Plug.Conn.t, { :ok, term } | { :error, term }, :public | :private) :: Plug.Conn.t
  def send_update_resp(conn, { :ok, entity }, privacy) do
    conn
    |> cache_entity(entity)
    |> cache(privacy)
    |> send_render(200, entity)
  end

  def send_update_resp(conn, { :error, errors }, _privacy) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity delete was successful,
  otherwise send validation failure response.
  """
  @spec send_delete_resp(Plug.Conn.t, :ok | { :error, term }, :public | :private) :: Plug.Conn.t
  def send_delete_resp(conn, :ok, privacy) do
    conn
    |> cache(privacy)
    |> send_resp(204, "")
  end

  def send_delete_resp(conn, { :error, errors }, _privacy) do
    send_validation_failed(conn, errors)
  end

  def send_validation_failed(conn, errors) do
    body = %{message: "Validation failed", errors: errors}
    send_render(conn, 422, body)
  end

  def cache(conn, privacy) do
    HexWeb.Plug.cache(conn, ["accept", "accept-encoding"],
                      [privacy] ++ ["max-age": @max_age])
  end
end
