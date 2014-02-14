defmodule ExplexWeb.Util do
  defexception BadRequest, [:message] do
    defimpl Plug.Exception do
      def status(_exception) do
        400
      end
    end
  end

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

  def read_body({ :ok, buffer, state }, acc, limit, adapter) when limit >= 0,
    do: read_body(adapter.stream_req_body(state, 1_000_000), acc <> buffer, limit - byte_size(buffer), adapter)
  def read_body({ :ok, _, state }, _acc, _limit, _adapter),
    do: { :too_large, state }

  def read_body({ :done, state }, acc, limit, _adapter) when limit >= 0,
    do: { :ok, acc, state }
  def read_body({ :done, state }, _acc, _limit, _adapter),
    do: { :too_large, state }

  def vendor_regex do
    ~r/^
        (?:\.(?<version>[^\+]+))?
        (?:\+(?<format>.*))?
        $/x
  end
end
