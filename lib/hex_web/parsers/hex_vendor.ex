defmodule HexWeb.Parsers.HexVendor do
  alias Plug.Conn

  @vendor_formats ~w(elixir erlang json)

  def parse(%Conn{} = conn, "application", "vnd.hex" <> rest, _headers, opts) do
    case Regex.run(HexWeb.Util.vendor_regex, rest) do
      [_, _version, vendor] when vendor in @vendor_formats ->
        {:ok, body, conn} = Conn.read_body(conn, opts)
        vendor(conn, vendor, body)

      _ ->
        {:next, conn}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp vendor(conn, "elixir", body) do
    case HexWeb.API.ElixirFormat.decode(body) do
      {:ok, params} ->
        {:ok, params, conn}
      {:error, reason} ->
        raise HexWeb.Plug.BadRequest, message: reason
    end
  end

  defp vendor(conn, "erlang", body) do
    case HexWeb.API.ErlangFormat.decode(body) do
      {:ok, params} ->
        {:ok, params, conn}
      {:error, reason} ->
        raise HexWeb.Plug.BadRequest, message: reason
    end
  end

  defp vendor(conn, "json", body) do
    case Poison.decode(body) do
      {:ok, params} ->
        {:ok, params, conn}
      _ ->
        raise HexWeb.Plug.BadRequest, message: "malformed JSON"
    end
  end
end
