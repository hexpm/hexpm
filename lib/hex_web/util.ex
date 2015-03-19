defmodule HexWeb.Util do
  @moduledoc """
  Assorted utility functions.
  """

  import Ecto.Query, only: [from: 2]
  require Logger

  def maybe(nil, _fun), do: nil
  def maybe(item, fun), do: fun.(item)

  def log_error(kind, error, stacktrace) do
    Logger.error Exception.format_banner(kind, error, stacktrace) <> "\n" <>
                 Exception.format_stacktrace(stacktrace)
  end

  def yesterday do
    {today, _time} = :calendar.universal_time()
    today_days = :calendar.date_to_gregorian_days(today)
    :calendar.gregorian_days_to_date(today_days - 1)
  end

  def ecto_now do
    Ecto.DateTime.from_erl(:calendar.universal_time)
  end

  defp diff(a, b) do
    {days, time} = :calendar.time_difference(a, b)
    :calendar.time_to_seconds(time) - (days * 24 * 60 * 60)
  end

  @doc """
  Determine if a given timestamp is less than a day (86400 seconds) old
  """
  def within_last_day(nil), do: false
  def within_last_day(a) do
    diff = diff(Ecto.DateTime.to_erl(a),
                :calendar.universal_time)

    diff < (24 * 60 * 60)
  end

  def etag(nil), do: nil
  def etag([]),  do: nil

  def etag(models) do
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
      model.updated_at
      |> Ecto.DateTime.to_erl
    end)

    Enum.max(list)
  end

  def parse_integer(string, default) when is_binary(string) do
    case Integer.parse(string) do
      {int, ""} -> int
      _ -> default
    end
  end
  def parse_integer(_, default), do: default

  def binarify(binary) when is_binary(binary),
    do: binary
  def binarify(number) when is_number(number),
    do: number
  def binarify(atom) when is_nil(atom) or is_boolean(atom),
    do: atom
  def binarify(atom) when is_atom(atom),
    do: Atom.to_string(atom)
  def binarify(list) when is_list(list),
    do: for(elem <- list, do: binarify(elem))
  def binarify(map) when is_map(map),
    do: for(elem <- map, into: %{}, do: binarify(elem))
  def binarify(tuple) when is_tuple(tuple),
    do: for(elem <- Tuple.to_list(tuple), do: binarify(elem)) |> List.to_tuple

  @doc """
  Returns a url to an API resource on the server from a list of path components.
  """
  @spec api_url([String.t] | String.t) :: String.t
  def api_url(path) do
    Application.get_env(:hex_web, :url) <> "/api/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the server from a list of path components.
  """
  @spec url([String.t] | String.t) :: String.t
  def url(path) do
    Application.get_env(:hex_web, :url) <> "/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the CDN from a list of path components.
  """
  @spec cdn_url([String.t] | String.t) :: String.t
  def cdn_url(path) do
    Application.get_env(:hex_web, :cdn_url) <> "/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the docs site from a list of path components.
  """
  @spec docs_url([String.t] | String.t) :: String.t
  def docs_url(path) do
    Application.get_env(:hex_web, :docs_url) <> "/" <> Path.join(List.wrap(path)) <> "/"
  end

  @doc """
  Converts an ecto datetime record to ISO 8601 format.
  """
  @spec to_iso8601(Ecto.DateTime.t) :: String.t
  def to_iso8601(dt) do
    list = [dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec]
    :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", list)
    |> IO.iodata_to_binary
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

  def paginate(query, page, count) do
    offset = (page - 1) * count
    from(var in query,
         offset: ^offset,
         limit: ^count)
  end

  @doc """
  Compares the two binaries in constant-time to avoid timing attacks.

  See: http://codahale.com/a-lesson-in-timing-attacks/
  """
  def secure_compare(left, right) do
    if byte_size(left) == byte_size(right) do
      arithmetic_compare(left, right, 0) == 0
    else
      false
    end
  end

  defp arithmetic_compare(<<x, left :: binary>>, <<y, right :: binary>>, acc) do
    import Bitwise
    arithmetic_compare(left, right, acc ||| (x ^^^ y))
  end

  defp arithmetic_compare("", "", acc) do
    acc
  end

  def shell(cmd) do
    stream = IO.binstream(:standard_io, :line)
    result = Porcelain.shell(cmd, out: stream, err: :out)
    result.status
  end

  if Mix.env == :test do
    def task_start(fun), do: fun.()
  else
    def task_start(fun), do: Task.start(fun)
  end
end
