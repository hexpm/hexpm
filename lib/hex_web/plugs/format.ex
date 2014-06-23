defmodule HexWeb.Plugs.Format do
  import Plug.Conn

  @vendor "hex"
  @allowed_versions ["beta"]

  def init(opts), do: opts

  def call(conn, _opts) do
    accepts = parse_accepts(conn)
    {format, version} = parse(accepts)

    if version in @allowed_versions do
      conn
      |> assign(:format, format)
      |> assign(:version, version)
      |> put_resp_header("x-hex-media-type", "#{@vendor}.#{version}")
    else
      raise Plug.Parsers.UnsupportedMediaTypeError
    end
  end

  defp parse(accepts) do
    {format, version} =
      Enum.find_value(accepts, {:unknown, nil}, fn
        {"*", "*"} ->
          {:json, nil}
        {"application", "*"} ->
          {:json, nil}
        {"application", "json"} ->
          {:json, nil}
        {"application", unquote("vnd." <> @vendor) <> rest} ->
          if result = Regex.run(HexWeb.Util.vendor_regex, rest) do
            destructure [_, version, format], result
            if version == "", do: version = nil

            {format(format), version}
          else
            {:json, nil}
          end
        _ ->
          nil
      end)

    if accepts == [] do
      format = :json
    end
    if nil?(version) do
      version = "beta"
    end

    {format, version}
  end

  defp format("elixir"), do: :elixir
  defp format(_),        do: :json

  defp parse_accepts(conn) do
    get_req_header(conn, "accept")
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.map(&:cowboy_http.content_type/1)
    |> Enum.reject(&match?({:error, _}, &1))
    |> Enum.map(&{elem(&1, 0), elem(&1, 1)})
  end
end
