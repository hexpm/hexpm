defmodule HexpmWeb.PlugParser do
  alias Plug.Conn

  @behaviour Plug.Parsers
  @formats ~w(erlang json)

  @impl true
  def init(opts) do
    opts
  end

  # Hex has sent Erlang terms since 0.11.0. An Elixir body has to be parsed as
  # code, which takes hundreds of times its size in memory, so it's refused
  # unread.
  @impl true
  def parse(%Conn{}, "application", "vnd.hex+elixir", _headers, _opts) do
    raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "application/vnd.hex+elixir"
  end

  def parse(%Conn{} = conn, "application", "vnd.hex+" <> format, _headers, opts)
      when format in @formats do
    decoder = get_decoder(format, opts)

    conn
    |> Conn.read_body(opts)
    |> decode(decoder)
  end

  # Okta and Entra send provisioning bodies as application/scim+json, which
  # the stock :json parser does not match; without this clause they arrive
  # unparsed and params are empty.
  def parse(%Conn{} = conn, "application", "scim+json", _headers, opts) do
    decoder = get_decoder("json", opts)

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
      "erlang" -> HexpmWeb.ErlangFormat
      "json" -> Keyword.fetch!(opts, :json_decoder)
    end
  end
end
