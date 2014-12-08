defmodule HexWeb.Parsers.Json do
  @doc """
  Parses JSON.
  """
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "json", _headers, opts) do
    {:ok, body, conn} = Conn.read_body(conn, opts)
    case Poison.decode(body) do
      {:ok, params} ->
        {:ok, params, conn}
      _ ->
        raise HexWeb.Plug.BadRequest, message: "malformed JSON"
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end
