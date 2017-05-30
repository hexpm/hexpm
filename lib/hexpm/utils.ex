defmodule Hexpm.Utils do
  @moduledoc """
  Assorted utility functions.
  """

  @timeout 60 * 60 * 1000

  import Ecto.Query, only: [from: 2]
  require Logger

  def multi_task(args, fun) do
    args
    |> multi_async(fun)
    |> multi_await
  end

  def multi_task(funs) do
    funs
    |> multi_async
    |> multi_await
  end

  def multi_async(args, fun) do
    Enum.map(args, fn arg -> Task.async(fn -> fun.(arg) end) end)
  end

  def multi_async(funs) do
    Enum.map(funs, &Task.async/1)
  end

  def multi_await(tasks) do
    Enum.map(tasks, &Task.await(&1, @timeout))
  end

  def maybe(nil, _fun), do: nil
  def maybe(item, fun), do: fun.(item)

  def log_error(kind, error, stacktrace) do
    Logger.error Exception.format_banner(kind, error, stacktrace) <> "\n" <>
                 Exception.format_stacktrace(stacktrace)
  end

  def utc_yesterday() do
    utc_days_ago(1)
  end

  def utc_days_ago(days) do
    {today, _time} = :calendar.universal_time()

    today
    |> :calendar.date_to_gregorian_days()
    |> Kernel.-(days)
    |> :calendar.gregorian_days_to_date()
    |> Date.from_erl!()
  end

  def safe_to_atom(binary, allowed) do
    if binary in allowed, do: String.to_atom(binary)
  end

  def safe_page(page, _count, _per_page) when page < 1,
    do: 1
  def safe_page(page, count, per_page) when page > div(count, per_page) + 1,
    do: div(count, per_page) + 1
  def safe_page(page, _count, _per_page),
    do: page

  def safe_int(nil), do: nil

  def safe_int(string) do
    case Integer.parse(string) do
      {int, ""} -> int
      _         -> nil
    end
  end

  def parse_search(nil), do: nil
  def parse_search(""), do: nil
  def parse_search(search), do: String.trim(search)

  defp diff(a, b) do
    {days, time} = :calendar.time_difference(a, b)
    :calendar.time_to_seconds(time) - (days * 24 * 60 * 60)
  end

  @doc """
  Determine if a given timestamp is less than a day (86400 seconds) old
  """
  def within_last_day(nil), do: false
  def within_last_day(a) do
    diff = diff(NaiveDateTime.to_erl(a),
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
      NaiveDateTime.to_erl(model.updated_at)
    end)

    Enum.max(list)
  end

  def safe_binary_to_term(binary, opts \\ [])

  def safe_binary_to_term(binary, opts) when is_binary(binary) do
    term = :erlang.binary_to_term(binary, opts)
    safe_terms(term)
    {:ok, term}
  catch
    :throw, :safe_terms ->
      :error
  end

  defp safe_terms(list) when is_list(list) do
    safe_list(list)
  end
  defp safe_terms(tuple) when is_tuple(tuple) do
    safe_tuple(tuple, tuple_size(tuple))
  end
  defp safe_terms(map) when is_map(map) do
    :maps.fold(fn key, value, acc ->
      safe_terms(key)
      safe_terms(value)
      acc
    end, map, map)
  end
  defp safe_terms(other) when is_atom(other) or is_number(other) or is_bitstring(other) or
                              is_pid(other) or is_reference(other) do
    other
  end
  defp safe_terms(_other) do
    throw :safe_terms
  end

  defp safe_list([]), do: :ok
  defp safe_list([h | t]) when is_list(t) do
    safe_terms(h)
    safe_list(t)
  end
  defp safe_list([h | t]) do
    safe_terms(h)
    safe_terms(t)
  end

  defp safe_tuple(_tuple, 0), do: :ok
  defp safe_tuple(tuple, n) do
    safe_terms(:erlang.element(n, tuple))
    safe_tuple(tuple, n - 1)
  end

  def binarify(term, opts \\ [])

  def binarify(binary, _opts) when is_binary(binary),
    do: binary
  def binarify(number, _opts) when is_number(number),
    do: number
  def binarify(atom, _opts) when is_nil(atom) or is_boolean(atom),
    do: atom
  def binarify(atom, _opts) when is_atom(atom),
    do: Atom.to_string(atom)
  def binarify(list, opts) when is_list(list),
    do: for(elem <- list, do: binarify(elem, opts))
  def binarify(%Version{} = version, _opts),
    do: to_string(version)
  def binarify(%NaiveDateTime{} = dt, _opts),
    do: dt |> Map.put(:microsecond, {0, 0}) |> NaiveDateTime.to_iso8601()
  def binarify(%{__struct__: atom}, _opts) when is_atom(atom),
    do: raise "not able to binarify %#{inspect atom}{}"
  def binarify(tuple, opts) when is_tuple(tuple),
    do: for(elem <- Tuple.to_list(tuple), do: binarify(elem, opts)) |> List.to_tuple
  def binarify(map, opts) when is_map(map) do
    if Keyword.get(opts, :maps, true) do
      for(elem <- map, into: %{}, do: binarify(elem, opts))
    else
      for(elem <- map, do: binarify(elem, opts))
    end
  end

  @doc """
  Returns a url to a resource on the CDN from a list of path components.
  """
  @spec cdn_url([String.t] | String.t) :: String.t
  def cdn_url(path) do
    Application.get_env(:hexpm, :cdn_url) <> "/" <> Path.join(List.wrap(path))
  end

  @doc """
  Returns a url to a resource on the docs site from a list of path components.
  """
  @spec docs_url(Hexpm.Repository.Package.t, Hexpm.Repository.Release.t) :: String.t
  @spec docs_url([String.t] | String.t) :: String.t
  def docs_url(package, release) do
    docs_url([package.name, to_string(release.version)])
  end
  def docs_url(path) do
    Application.get_env(:hexpm, :docs_url) <> "/" <> Path.join(List.wrap(path)) <> "/"
  end

  @doc """
  Returns a url to the documentation tarball in the Amazon S3 Hex.pm bucket.
  """
  @spec docs_tarball_url(Hexpm.Repository.Package.t, Hexpm.Repository.Release.t) :: String.t
  def docs_tarball_url(package, release) do
    repo    = Application.get_env(:hexpm, :cdn_url)
    package = package.name
    version = to_string(release.version)
    "#{repo}/docs/#{package}-#{version}.tar.gz"
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

  def paginate(query, page, count) when is_integer(page) and page > 0 do
    offset = (page - 1) * count
    from(var in query,
         offset: ^offset,
         limit: ^count)
  end

  def paginate(query, _page, count) do
    paginate(query, 1, count)
  end

  def shell(cmd) do
    IO.puts("$ " <> cmd)
    stream = IO.binstream(:standard_io, :line)
    result = Porcelain.shell(cmd, out: stream, err: :out)
    result.status
  end

  def sign(payload, key) do
    [entry | _] = :public_key.pem_decode(key)
    key = :public_key.pem_entry_decode(entry)
    :public_key.sign(payload, :sha512, key)
  end

  def verify(payload, signature, key) do
    [entry | _] = :public_key.pem_decode(key)
    key = :public_key.pem_entry_decode(entry)
    :public_key.verify(payload, :sha512, signature, key)
  end

  def parse_ip(ip) do
    parts = String.split(ip, ".")
    if length(parts) == 4 do
      parts = Enum.map(parts, &String.to_integer/1)
      for part <- parts, into: <<>>, do: <<part>>
    end
  end
end
