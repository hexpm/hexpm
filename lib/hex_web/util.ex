defmodule HexWeb.Util do
  @moduledoc """
  Assorted utility functions.
  """

  import Ecto.Query, only: [from: 2]
  require Stout

  def maybe(nil, _fun), do: nil
  def maybe(item, fun), do: fun.(item)

  def log_error(kind, error, stacktrace) do
    Stout.error Exception.format_banner(kind, error, stacktrace) <> "\n"
                <> Exception.format_stacktrace(stacktrace)
  end

  def yesterday do
    {today, _time} = :calendar.universal_time()
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
      {int, ""} -> int
      _ -> default
    end
  end
  def parse_integer(_, default), do: default

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
  Returns a url to a resource on the server from a list of path components.
  """
  @spec cdn_url([String.t] | String.t) :: String.t
  def cdn_url(path) do
    Application.get_env(:hex_web, :cdn_url) <> "/" <> Path.join(List.wrap(path))
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
         offset: offset,
         limit: count)
  end
end
