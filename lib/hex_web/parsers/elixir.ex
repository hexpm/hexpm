defmodule HexWeb.Parsers.Elixir do
  @doc """
  Safely parses an elixir term.

  Safely means that no code evaluated or new atoms will be created.
  """
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "vnd.hex" <> rest, _headers, opts) do
    case Regex.run(HexWeb.Util.vendor_regex, rest) do
      [_, _version, "elixir"] ->
        {:ok, body, conn } = Conn.read_body(conn, opts)

        case HexWeb.API.ElixirFormat.decode(body) do
          {:ok, params} ->
            {:ok, params, conn}
          {:error, reason} ->
            raise HexWeb.Util.BadRequest, message: reason
          end

      _ ->
        { :next, conn }
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    { :next, conn }
  end
end
