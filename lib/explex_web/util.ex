defmodule ExplexWeb.Util do
  def url(path) do
    { :ok, url } = :application.get_env(:explex_web, :api_url)
    url <> "/" <> Path.join(List.wrap(path))
  end

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
end
