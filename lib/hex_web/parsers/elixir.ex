defmodule HexWeb.Parsers.Elixir do
  @doc """
  Safely parses an elixir term.

  Safely means that no code evaluated or new atoms will be created.
  """
  alias Plug.Conn

  def parse(Conn[] = conn, "application", "vnd.hex" <> rest, _headers, opts) do
    case Regex.run(HexWeb.Util.vendor_regex, rest) do
      [_, _version, "elixir"] ->
        read_body(conn, Keyword.fetch!(opts, :limit))
      _ ->
        { :next, conn }
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    { :next, conn }
  end

  defp read_body(Conn[adapter: { adapter, state }] = conn, limit) do
    case HexWeb.Util.read_body({ :ok, "", state }, "", limit, adapter) do
      { :too_large, state } ->
        { :too_large, conn.adapter({ adapter, state }) }
      { :ok, "", state } ->
        { :ok, [], conn.adapter({ adapter, state }) }
      { :ok, body, state } ->
        params = decode(body)
        { :ok, params, conn.adapter({ adapter, state }) }
    end
  end

  defp decode(body) do
    case Code.string_to_quoted(body, existing_atoms_only: true) do
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
end
