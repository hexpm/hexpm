defmodule HexpmWeb.Plugs.ValidateParams do
  @moduledoc """
  Refuses a request whose host, path or parameters hold text Postgres can't
  store, a NUL byte or invalid UTF-8, before any query reads them.

  It runs in the endpoint right after the body is parsed, so it covers every
  route whether or not it goes through a pipeline. No format has been
  negotiated that early, so it raises, and the endpoint's error rendering
  answers 400 in the format the client accepts, as it does for a body that
  doesn't parse.
  """

  @behaviour Plug

  defmodule InvalidTextError do
    defexception message: "the request contains a NUL byte or invalid UTF-8", plug_status: 400
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Hexpm.Utils.storable_text?(conn.host) and storable_path?(conn.path_info) and
         Hexpm.Utils.storable_text?(conn.params) do
      conn
    else
      raise InvalidTextError
    end
  end

  # The router decodes path segments into path params later, so they are still
  # percent-encoded here. A segment that doesn't decode is the router's to
  # refuse.
  defp storable_path?(segments) do
    Enum.all?(segments, fn segment ->
      case decode(segment) do
        {:ok, decoded} -> Hexpm.Utils.storable_text?(decoded)
        :error -> true
      end
    end)
  end

  defp decode(segment) do
    {:ok, URI.decode(segment)}
  rescue
    ArgumentError -> :error
  end
end
