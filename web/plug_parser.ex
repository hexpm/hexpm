defmodule HexWeb.PlugParser do
  alias Plug.Conn

  @formats ~w(elixir erlang json)

  def parse(%Conn{} = conn, "application", "vnd.hex+" <> format, _headers, opts)
      when format in @formats do

    conn
    |> Conn.read_body(opts)
    |> decode(format)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:more, _, conn}, _format) do
    {:error, :too_large, conn}
  end

  defp decode({:ok, "", conn}, _format) do
    {:ok, %{}, conn}
  end

  defp decode({:ok, body, conn}, "elixir") do
    case HexWeb.ElixirFormat.decode(body) do
      {:ok, terms} when is_map(terms) ->
        {:ok, terms, conn}
      {:ok, terms} ->
        {:ok, %{"_json" => terms}, conn}
      {:error, reason} ->
        raise HexWeb.Plugs.BadRequestError, message: reason
    end
  end

  defp decode({:ok, body, conn}, "erlang") do
    case HexWeb.ErlangFormat.decode(body) do
      {:ok, terms} when is_map(terms) ->
        {:ok, terms, conn}
      {:ok, terms} ->
        {:ok, %{"_json" => terms}, conn}
      {:error, reason} ->
        raise HexWeb.Plugs.BadRequestError, message: reason
    end
  end

  defp decode({:ok, body, conn}, "json") do
    case Poison.decode(body) do
      {:ok, terms} when is_map(terms) ->
        {:ok, terms, conn}
      {:ok, terms} ->
        {:ok, %{"_json" => terms}, conn}
      _ ->
        raise HexWeb.Plugs.BadRequestError, message: "malformed JSON"
    end
  end
end
