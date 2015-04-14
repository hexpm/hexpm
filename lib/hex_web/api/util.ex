defmodule HexWeb.API.Util do
  @doc """
  API related utility functions.
  """

  require Record
  import Plug.Conn
  alias HexWeb.User
  alias HexWeb.API.Key

  @max_age 60

  def when_stale(conn, entities, opts \\ [], fun) do
    if etag = HexWeb.Util.etag(entities) do
      conn = put_resp_header(conn, "etag", etag)
    end

    if Keyword.get(opts, :modified, true) do
      if modified = HexWeb.Util.last_modified(entities) do
        conn = put_resp_header(conn, "last-modified", :cowboy_clock.rfc1123(modified))
      end
    end

    unless HexWeb.API.Util.fresh?(conn, etag: etag, modified: modified) do
      fun.(conn)
    else
      send_resp(conn, 304, "")
    end
  end

  def fresh?(conn, opts) do
    modified_since = List.first get_req_header(conn, "if-modified-since")
    none_match     = List.first get_req_header(conn, "if-none-match")

    fresh = false

    if modified_since && opts[:modified] do
      fresh = not_modified?(modified_since, opts[:modified])
    end

    if none_match && opts[:etag] do
      fresh = etag_matches?(none_match, opts[:etag])
    end

    fresh
  end

  defp not_modified?(modified_since, last_modified) do
    modified_since = :cowboy_http.rfc1123_date(modified_since)
    modified_since = :calendar.datetime_to_gregorian_seconds(modified_since)
    last_modified  = :calendar.datetime_to_gregorian_seconds(last_modified)
    last_modified <= modified_since
  end

  defp etag_matches?(none_match, etag) do
    Plug.Conn.Utils.list(none_match)
    |> Enum.any?(&(&1 in [etag, "*"]))
  end

  @doc """
  Renders an entity or dict body and sends it with a status code.
  """
  @spec send_render(Plug.Conn.t, non_neg_integer, term) :: Plug.Conn.t
  def send_render(conn, status, body) do
    body = render(body)
    send_body(conn, status, body, false)
  end

  defp render(nil) do
    nil
  end

  defp render(%{__struct__: _} = model) do
    HexWeb.Render.render(model)
  end

  defp render(list) when is_list(list) do
    Enum.map(list, &render/1)
  end

  defp render(map) when is_map(map) do
    map
  end

  def send_body(conn, status, nil, _fallback) do
    send_resp(conn, status, "")
  end

  def send_body(conn, status, body, fallback) do
    case conn.assigns[:format] do
      :elixir ->
        body = HexWeb.API.ElixirFormat.encode(body)
        content_type = "application/vnd.hex+elixir"
      :erlang ->
        body = HexWeb.API.ErlangFormat.encode(body)
        content_type = "application/vnd.hex+erlang"
      format when format == :json or fallback ->
        body = Poison.encode!(body, pretty: true)
        content_type = "application/json"
      _ ->
        raise Plug.Parsers.UnsupportedMediaTypeError
    end

    conn
    |> put_resp_header("content-type", content_type)
    |> send_resp(status, body)
  end


  @doc """
  Run the given function if a user authorized as specified user,
  otherwise send an unauthorized response.
  """
  @spec with_authorized(Plug.Conn.t, Keyword.t, (HexWeb.User.t -> boolean), (HexWeb.User.t -> any)) :: any
  def with_authorized(conn, opts, auth? \\ fn _ -> true end, fun) do
    case authorize(conn, opts) do
      {:ok, user} ->
        if auth?.(user) do
          fun.(user)
        else
          send_unauthorized(conn)
        end
      {:unconfirmed, _user} ->
        send_unconfirmed(conn)
      :error ->
        send_unauthorized(conn)
    end
  end

  # Check if a user is authorized, return `{:ok, user}` if so,
  # or `:error` if authorization failed
  defp authorize(conn, opts) do
    only_basic = Keyword.get(opts, :only_basic, false)
    allow_unconfirmed = Keyword.get(opts, :allow_unconfirmed, false)

    result =
      case get_req_header(conn, "authorization") do
        ["Basic " <> credentials] ->
          basic_auth(credentials)
        [key] when not only_basic ->
          key_auth(key)
        _ ->
          :error
      end

    case result do
      {:ok, user} ->
        cond do
          allow_unconfirmed or user.confirmed ->
            {:ok, user}
          !user.confirmed ->
            {:unconfirmed, user}
          true ->
            :error
        end
      error ->
        error
    end
  end

  defp basic_auth(credentials) do
    case String.split(:base64.decode(credentials), ":", parts: 2) do
      [username, password] ->
        user = User.get(username: username)
        if User.auth?(user, password) do
          {:ok, user}
        else
          :error
        end
      _ ->
        :error
    end
  end

  defp key_auth(key) do
    case Key.auth(key) do
      nil ->
        :error
      user ->
        {:ok, user}
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
  Send an unconfirmed response.
  """
  @spec send_unconfirmed(Plug.Conn.t) :: Plug.Conn.t
  def send_unconfirmed(conn) do
    errors = %{user: "account needs to be confirmed"}
    body = %{message: "Account Unconfirmed", errors: errors}

    conn
    |> put_resp_header("www-authenticate", "Basic realm=hex")
    |> send_render(403, body)
  end

  @spec send_okay(Plug.Conn.t, term, :public | :private) :: Plug.Conn.t
  def send_okay(conn, entity, privacy) do
    conn
    |> cache(privacy)
    |> send_render(200, entity)
  end

  @doc """
  Send a creation response if entity creation was successful,
  otherwise send validation failure response.
  """
  @spec send_creation_resp(Plug.Conn.t, {:ok, term} | {:error, term}, :public | :private, String.t) :: Plug.Conn.t
  def send_creation_resp(conn, {:ok, entity}, privacy, location) do
    conn
    |> put_resp_header("location", location)
    |> cache(privacy)
    |> send_render(201, entity)
  end

  def send_creation_resp(conn, {:error, errors}, _privacy, _location) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity update was successful,
  otherwise send validation failure response.
  """
  @spec send_update_resp(Plug.Conn.t, {:ok, term} | {:error, term}, :public | :private) :: Plug.Conn.t
  def send_update_resp(conn, {:ok, entity}, privacy) do
    conn
    |> cache(privacy)
    |> send_render(200, entity)
  end

  def send_update_resp(conn, {:error, errors}, _privacy) do
    send_validation_failed(conn, errors)
  end

  @doc """
  Send an ok response if entity delete was successful,
  otherwise send validation failure response.
  """
  @spec send_delete_resp(Plug.Conn.t, :ok | {:error, term}, :public | :private) :: Plug.Conn.t
  def send_delete_resp(conn, :ok, privacy) do
    conn
    |> cache(privacy)
    |> send_resp(204, "")
  end

  def send_delete_resp(conn, {:error, errors}, _privacy) do
    send_validation_failed(conn, errors)
  end

  def send_validation_failed(conn, errors) do
    errors = errors_to_map(errors)
    body = %{message: "Validation failed", errors: errors}
    send_render(conn, 422, body)
  end

  def cache(conn, privacy) do
    HexWeb.Plug.cache(conn, ["accept", "accept-encoding"],
                      [privacy] ++ ["max-age": @max_age])
  end

  defp errors_to_map(tuple) when is_tuple(tuple) do
    Tuple.to_list(tuple) |> Enum.map(&errors_to_map/1) |> List.to_tuple
  end

  defp errors_to_map([{_, _}|_] = list) do
    Enum.into(list, %{}, &errors_to_map/1)
  end

  defp errors_to_map(term) do
    term
  end
end
