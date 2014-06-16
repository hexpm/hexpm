defmodule HexWeb.Util do
  @moduledoc """
  Assorted utility functions.
  """

  import Ecto.Query, only: [from: 2]
  require Stout

  def maybe(nil, _fun), do: nil
  def maybe(item, fun), do: fun.(item)

  def json_encode(map) do
    Jazz.encode!(map)
  end

  def json_decode!(json) do
    Jazz.decode!(json)
  end

  def json_decode(json) do
    Jazz.decode(json)
  end

  def log_error(kind, error, stacktrace) do
    Stout.error Exception.format_banner(kind, error, stacktrace) <> "\n"
                <> Exception.format_stacktrace(stacktrace)
  end

  def yesterday do
    { today, _time } = :calendar.universal_time()
    today_days = :calendar.date_to_gregorian_days(today)
    :calendar.gregorian_days_to_date(today_days - 1)
  end

  def ecto_now do
    Ecto.DateTime.from_erl(:calendar.universal_time)
  end

  def etag(models) do
    list = Enum.map(List.wrap(models), fn model ->
      [ model.__struct__, model.id, model.updated_at ]
    end)

    binary = :erlang.term_to_binary(list)
    :crypto.hash(:md5, binary)
    |> Base.encode16(case: :lower)
  end

  def parse_integer(string, default) when is_binary(string) do
    case Integer.parse(string) do
      { int, "" } -> int
      _ -> default
    end
  end
  def parse_integer(_, default), do: default

  @doc """
  Returns a url to an API resource on the server from a list of path components.
  """
  @spec api_url([String.t] | String.t) :: String.t
  def api_url(path) do
    HexWeb.Config.url <> "/api/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the server from a list of path components.
  """
  @spec url([String.t] | String.t) :: String.t
  def url(path) do
    HexWeb.Config.url <> "/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the server from a list of path components.
  """
  @spec cdn_url([String.t] | String.t) :: String.t
  def cdn_url(path) do
    HexWeb.Config.cdn_url <> "/" <> Path.join(List.wrap(path))
  end

  @doc """
  Converts an ecto datetime record to ISO 8601 format.
  """
  @spec to_iso8601(Ecto.DateTime.t) :: String.t
  def to_iso8601(dt) do
    list = [dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec]
    :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", list)
    |> iodata_to_binary
  end

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

  def binarify(binary) when is_binary(binary),
    do: binary
  def binarify(number) when is_number(number),
    do: number
  def binarify(atom) when nil?(atom) or is_boolean(atom),
    do: atom
  def binarify(atom) when is_atom(atom),
    do: atom_to_binary(atom)
  def binarify(list) when is_list(list),
    do: for(elem <- list, do: binarify(elem))
  def binarify(map) when is_map(map),
    do: for(elem <- map, into: %{}, do: binarify(elem))
  def binarify(tuple) when is_tuple(tuple),
    do: for(elem <- tuple_to_list(tuple), do: binarify(elem)) |> list_to_tuple

  def safe_deserialize_elixir("") do
    nil
  end

  def safe_deserialize_elixir(string) do
    case Code.string_to_quoted(string, existing_atoms_only: true) do
      { :ok, ast } ->
        if safe_term?(ast) do
          Code.eval_quoted(ast)
          |> elem(0)
          |> list_to_map
        else
          raise HexWeb.Util.BadRequest, message: "unsafe elixir"
        end
      _ ->
        raise HexWeb.Util.BadRequest, message: "malformed elixir"
    end
  end

  def safe_eval(ast) do
    if safe_term?(ast) do
      Code.eval_quoted(ast)
      |> elem(0)
      |> list_to_map
    else
      raise HexWeb.Util.BadRequest, message: "unsafe elixir"
    end
  end

  def safe_term?({func, _, terms}) when func in [:{}, :%{}] and is_list(terms) do
    Enum.all?(terms, &safe_term?/1)
  end

  def safe_term?(nil), do: true
  def safe_term?(term) when is_number(term), do: true
  def safe_term?(term) when is_binary(term), do: true
  def safe_term?(term) when is_boolean(term), do: true
  def safe_term?(term) when is_list(term), do: Enum.all?(term, &safe_term?/1)
  def safe_term?(term) when is_tuple(term), do: Enum.all?(tuple_to_list(term), &safe_term?/1)
  def safe_term?(_), do: false

  defp list_to_map(list) when is_list(list) do
    if list == [] or is_tuple(List.first(list)) do
      Enum.into(list, %{}, fn
        { key, list } when is_list(list) -> { key, list_to_map(list) }
        other -> list_to_map(other)
      end)
    else
      Enum.map(list, &list_to_map/1)
    end
  end

  defp list_to_map(other) do
    other
  end

  def paginate(query, page, count) do
    offset = (page - 1) * count
    from(var in query,
         offset: offset,
         limit: count)
  end
end
