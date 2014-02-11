defmodule ExplexWeb.Util.Plugs do
  import Plug.Connection

  def accept(conn, opts) do
    vendor = opts[:vendor]
    allow = opts[:allow]
    { mimes, formats } = Enum.partition(allow, &is_tuple/1)

    if accept = conn.req_headers["accept"] do
      types = Enum.map(String.split(accept, ","), &:cowboy_http.content_type/1)
      if Enum.find(types, &match?({ :error, _ }, &1)) do
        raise Plug.Parsers.UnsupportedMediaTypeError
      end


      if types != [] do
        accepted =
          Enum.find(types, fn type ->
            Enum.find(mimes, &match_mime?(type, &1))
          end)

        if accepted do
          conn = assign(conn, :format, elem(accepted, 1))
        else
          case Enum.find_value(types, &match_vendor?(&1, vendor, formats)) do
            { version, format } ->
              conn = conn
                     |> assign(:format, format)
                     |> assign(:version, version)
            _ ->
              raise Plug.Parsers.UnsupportedMediaTypeError
          end
        end
      end
    end

    unless conn.assigns[:format] do
      conn = assign(conn, :format, List.first(formats))
    end
    conn
  end

  @vendor_regex ~r/^
      (?:\.(?<version>[^\+]+))?
      (?:\+(?<format>.*))?
      $/x

  defp match_mime?({ "*", "*", _ }, _),
    do: true
  defp match_mime?({ first, "*", _ }, { first, _ }),
    do: true
  defp match_mime?({ first, second, _ }, { first, second }),
    do: true
  defp match_mime?(_, _),
    do: false

  defp match_vendor?({ "*", "*", _ }, _, formats),
    do: { nil, List.first(formats) }

  defp match_vendor?({ "application", second, _ }, vendor, formats) do
    case :binary.split(second, "vnd." <> vendor) do
      ["", rest] ->
        if result = Regex.run(@vendor_regex, rest) do
          destructure [_, version, format], result
          if version == "", do: version = nil
          if format == "", do: format = nil
          if nil?(format) or format in formats do
            { version, format }
          end
        end
      _ ->
        nil
    end
  end
end
