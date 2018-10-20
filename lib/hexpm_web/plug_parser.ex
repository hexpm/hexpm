defmodule HexpmWeb.PlugParser do
  alias Plug.Conn

  @formats ~w(elixir erlang json)

  def parse(%Conn{} = conn, "application", "vnd.hex+" <> format, _headers, opts)
      when format in @formats do
    decoder = get_decoder(format, opts)

    conn
    |> Conn.read_body(opts)
    |> decode(decoder)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:more, _, conn}, _decoder) do
    {:error, :too_large, conn}
  end

  defp decode({:error, :timeout}, _decoder) do
    raise Plug.TimeoutError
  end

  defp decode({:error, _}, _decoder) do
    raise Plug.BadRequestError
  end

  defp decode({:ok, "", conn}, _decoder) do
    {:ok, %{}, conn}
  end

  defp decode({:ok, body, conn}, decoder) do
    case decoder.decode(body) do
      {:ok, terms} when is_map(terms) ->
        {:ok, terms, conn}

      {:ok, terms} ->
        {:ok, %{"_json" => terms}, conn}

      {:error, reason} ->
        raise Plug.BadRequestError, message: reason
    end
  end

  defp get_decoder(format, opts) do
    case format do
      "elixir" -> HexpmWeb.ElixirFormat
      "erlang" -> HexpmWeb.ErlangFormat
      "json" -> Keyword.fetch!(opts, :json_decoder)
    end
  end
end
