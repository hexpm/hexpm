defmodule HexWeb.ControllerHelpers do
  import Plug.Conn
  import Phoenix.Controller

  @max_cache_age 60

  def cache(conn, control, vary) do
    conn
    |> maybe_put_resp_header("cache-control", parse_control(control))
    |> maybe_put_resp_header("vary", parse_vary(vary))
  end

  def api_cache(conn, privacy) do
    control = [privacy] ++ ["max-age": @max_cache_age]
    vary    = ["accept", "accept-encoding"]
    cache(conn, control, vary)
  end

  defp parse_vary(nil),  do: nil
  defp parse_vary(vary), do: Enum.map_join(vary, ", ", &"#{&1}")

  defp parse_control(nil), do: nil
  defp parse_control(control) do
    Enum.map_join(control, ", ", fn
      atom when is_atom(atom) -> "#{atom}"
      {key, value}          -> "#{key}=#{value}"
    end)
  end

  defp maybe_put_resp_header(conn, _header, nil),
    do: conn
  defp maybe_put_resp_header(conn, header, value),
    do: put_resp_header(conn, header, value)

  def validation_failed(conn, errors) do
    errors = lists_to_maps(errors)

    conn
    |> put_status(422)
    |> render(HexWeb.ErrorView, :"422", errors: errors)
  end

  defp lists_to_maps({x, y}),
    do: {lists_to_maps(x), lists_to_maps(y)}
  defp lists_to_maps([{_, _}|_] = list),
    do: Enum.into(list, %{}, &lists_to_maps/1)
  defp lists_to_maps(map) when is_map(map),
    do: Enum.into(map, %{}, &lists_to_maps/1)
  defp lists_to_maps(list) when is_list(list),
    do: Enum.map(list, &lists_to_maps/1)
  defp lists_to_maps(other),
    do: other

  def not_found(conn) do
    conn
    |> put_status(404)
    |> render(HexWeb.ErrorView, :"404")
  end

  def when_stale(conn, entities, opts \\ [], fun) do
    if etag = etag(entities) do
      conn = put_resp_header(conn, "etag", etag)
    end

    modified = nil

    if Keyword.get(opts, :modified, true) &&
       (modified = last_modified(entities)) do
      conn = put_resp_header(conn, "last-modified", :cowboy_clock.rfc1123(modified))
    end

    unless fresh?(conn, etag: etag, modified: modified) do
      fun.(conn)
    else
      send_resp(conn, 304, "")
    end
  end

  defp fresh?(conn, opts) do
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

  defp etag(nil), do: nil
  defp etag([]),  do: nil

  defp etag(models) do
    list = Enum.map(List.wrap(models), fn model ->
      [model.__struct__, model.id, model.updated_at]
    end)

    binary = :erlang.term_to_binary(list)
    :crypto.hash(:md5, binary)
    |> Base.encode16(case: :lower)
  end

  def last_modified(nil), do: nil
  def last_modified([]),  do: nil

  def last_modified(models) do
    list = Enum.map(List.wrap(models), fn model ->
      Ecto.DateTime.to_erl(model.updated_at)
    end)

    Enum.max(list)
  end
end
