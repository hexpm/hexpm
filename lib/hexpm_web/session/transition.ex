defmodule HexpmWeb.Session.Transition do
  alias Plug.Session.COOKIE

  @behaviour Plug.Session.Store

  # Session store that reads both encrypted cookie sessions and legacy
  # database-backed sessions (HexpmWeb.Session), but only ever writes
  # cookies. Legacy sessions are marked so MigrateSession can rewrite them
  # on their first request. Once the legacy cookies have aged out the
  # database fallback, the sessions table, and the purge job step can go.

  @legacy_marker "__legacy__"

  def legacy_marker(), do: @legacy_marker

  def init(opts) do
    COOKIE.init(opts)
  end

  def get(conn, cookie, opts) do
    case COOKIE.get(conn, cookie, opts) do
      {_sid, data} when data != %{} ->
        {nil, data}

      _ ->
        case HexpmWeb.Session.get(conn, cookie, :ok) do
          {nil, _data} ->
            {nil, %{}}

          {legacy_sid, data} ->
            {{:legacy, legacy_sid}, Map.put(data, @legacy_marker, true)}
        end
    end
  end

  def put(conn, _sid, data, opts) do
    COOKIE.put(conn, nil, Map.delete(data, @legacy_marker), opts)
  end

  def delete(conn, {:legacy, legacy_sid}, _opts) do
    HexpmWeb.Session.delete(conn, legacy_sid, :ok)
  end

  def delete(_conn, _sid, _opts) do
    :ok
  end
end
