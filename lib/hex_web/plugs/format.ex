defmodule HexWeb.Plugs.Format do
  import Plug.Connection

  @vendor "hex"
  @allowed_versions ["beta"]

  def init(opts), do: opts

  def call(conn, _opts) do
    { format, version } = parse(conn)

    if version in @allowed_versions do
      conn
      |> assign(:format, format)
      |> assign(:version, version)
      |> put_resp_header("x-hex-media-type", "#{@vendor}.#{version}")
    else
      raise Plug.Parsers.UnsupportedMediaTypeError
    end
  end

  defp parse(conn) do
    accepts = conn.assigns[:accepts]

    { format, version } =
      Enum.find_value(accepts, { :unknown, nil }, fn
        { "*", "*" } ->
          { :json, nil }
        { "application", "*" } ->
          { :json, nil }
        { "application", "json" } ->
          { :json, nil }
        { "application", unquote("vnd." <> @vendor) <> rest } ->
          if result = Regex.run(HexWeb.Util.vendor_regex, rest) do
            destructure [_, version, format], result
            if version == "", do: version = nil

            { format(format), version }
          else
            { :json, nil }
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

    { format, version }
  end

  defp format("elixir"), do: :elixir
  defp format(_),        do: :json
end
