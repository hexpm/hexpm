defmodule HexWeb.Parsers.Erlang do
  @doc """
  Safely parses an erlang term encoded with `:erlang.term_to_binary`.

  Safely means that no new atoms will be created.
  """
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "vnd.hex" <> rest, _headers, opts) do
    case Regex.run(HexWeb.Util.vendor_regex, rest) do
      [_, _version, "erlang"] ->
        {:ok, body, conn} = Conn.read_body(conn, opts)

        case HexWeb.API.ErlangFormat.decode(body) do
          {:ok, params} ->
            {:ok, params, conn}
          {:error, reason} ->
            raise HexWeb.Plug.BadRequest, message: reason
        end

      _ ->
        {:next, conn}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end
