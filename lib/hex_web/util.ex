defmodule HexWeb.Util do
  @moduledoc """
  Assorted utility functions.
  """

  import Ecto.Query, only: [from: 2]

  defexception BadRequest, [:message] do
    defimpl Plug.Exception do
      def status(_exception) do
        400
      end
    end
  end

  @doc """
  Returns a url to an API resource on the server from a list of path components.
  """
  @spec api_url([String.t]) :: String.t
  def api_url(path) do
    HexWeb.Config.url <> "/api/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the server from a list of path components.
  """
  @spec url([String.t]) :: String.t
  def url(path) do
    HexWeb.Config.url <> "/" <> Path.join(List.wrap(path))
  end

  @doc """
  Converts an ecto datetime record to ISO 8601 format.
  """
  @spec to_iso8601(Ecto.DateTime.t) :: String.t
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

  @doc """
  Read the body from a Plug connection.

  Should be in Plug proper eventually and can be removed at that point.
  """
  def read_body(Plug.Conn[adapter: { adapter, state }] = conn, limit) do
    case read_body({ :ok, "", state }, "", limit, adapter) do
      { :too_large, state } ->
        { :too_large, conn.adapter({ adapter, state }) }
      { :ok, body, state } ->
        { :ok, body, conn.adapter({ adapter, state }) }
    end
  end

  def read_body!(Plug.Conn[adapter: { adapter, state }] = conn, limit) do
    case read_body({ :ok, "", state }, "", limit, adapter) do
      { :too_large, _state } ->
        raise Plug.Parsers.RequestTooLargeError
      { :ok, body, state } ->
        { body, conn.adapter({ adapter, state }) }
    end
  end

  defp read_body({ :ok, buffer, state }, acc, limit, adapter) when limit >= 0,
    do: read_body(adapter.stream_req_body(state, 1_000_000), acc <> buffer, limit - byte_size(buffer), adapter)
  defp read_body({ :ok, _, state }, _acc, _limit, _adapter),
    do: { :too_large, state }

  defp read_body({ :done, state }, acc, limit, _adapter) when limit >= 0,
    do: { :ok, acc, state }
  defp read_body({ :done, state }, _acc, _limit, _adapter),
    do: { :too_large, state }

  @doc """
  A regex parsing out the version and format at the end of a media type.
  '.version+format'
  """
  @spec vendor_regex() :: Regex.t
  def vendor_regex do
    ~r/^
        (?:\.(?<version>[^\+]+))?
        (?:\+(?<format>.*))?
        $/x
  end

  @doc """
  Encode an elixir term that can be safely deserialized on another machine.
  """
  @spec safe_serialize_elixir(term) :: String.t
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

  def safe_deserialize_elixir("") do
    nil
  end

  def safe_deserialize_elixir(string) do
    case Code.string_to_quoted(string, existing_atoms_only: true) do
      { :ok, ast } ->
        if Macro.safe_term(ast) do
          Code.eval_quoted(ast) |> elem(0)
        else
          raise HexWeb.Util.BadRequest, message: "unsafe elixir"
        end
      _ ->
        raise HexWeb.Util.BadRequest, message: "malformed elixir"
    end
  end

  def paginate(query, page, count) do
    offset = (page - 1) * count
    from(var in query,
         offset: offset,
         limit: count)
  end

  def searchinate(query, _field, nil), do: query

  def searchinate(query, field, search) do
    search = escape(search, ~r"(%|_)") <> "%"
    from(var in query, where: ilike(field(var, ^field), ^search))
  end

  defp escape(string, escape) do
    String.replace(string, escape, "\\\\\\1")
  end

  def hexify(bin) do
    bc << high :: size(4), low :: size(4) >> inbits bin do
      << hex_char(high), hex_char(low) >>
    end
  end

  defp hex_char(n) when n < 10, do: ?0 + n
  defp hex_char(n) when n < 16, do: ?a - 10 + n

  def dehexify(bin) do
    int  = :erlang.binary_to_integer(bin, 16)
    size = byte_size(bin)
    << int :: [integer, unit(4), size(size)] >>
  end
end
