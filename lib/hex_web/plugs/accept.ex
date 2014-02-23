defmodule HexWeb.Plugs.Accept do
  import Plug.Connection

  def init(opts), do: opts

  def call(conn, opts) do
    vendor = opts[:vendor]
    allow  = opts[:allow]
    { mimes, formats } = Enum.partition(allow, &is_tuple/1)

    if accept = conn.req_headers["accept"] do
      types = Enum.map(String.split(accept, ","), &:cowboy_http.content_type/1)
       if Enum.find(types, &match?({ :error, _ }, &1)) do
        conn
      else
        check_accept(conn, types, mimes, vendor, formats)
      end
    else
      assign(conn, :format, List.first(formats))
    end
  end

  defp check_accept(conn, [], _mimes, _vendor, formats),
    do: assign(conn, :format, List.first(formats))

  defp check_accept(conn, types, mimes, vendor, formats) do
    accepted =
      Enum.find_value(types, fn type ->
        Enum.find_value(mimes, &match_mime?(type, &1))
      end)
    if accepted do
      assign(conn, :format, elem(accepted, 1))
    else
      case Enum.find_value(types, &match_vendor?(&1, vendor, formats)) do
        { version, format } ->
          conn
          |> assign(:format, format)
          |> assign(:version, version)
        _ ->
          conn
      end
    end
  end

  defp match_mime?({ "*", "*", _ }, media),
    do: media
  defp match_mime?({ first, "*", _ }, { first, _ } = media),
    do: media
  defp match_mime?({ first, second, _ }, { first, second } = media),
    do: media
  defp match_mime?(_, _),
    do: nil

  defp match_vendor?({ "application", second, _ }, vendor, formats) do
    case :binary.split(second, "vnd." <> vendor) do
      ["", rest] ->
        if result = Regex.run(HexWeb.Util.vendor_regex, rest) do
          destructure [_, version, format], result
          if version == "", do: version = nil
          if format == "", do: format = nil
          { version, format || List.first(formats) }
        end
      _ ->
        nil
    end
  end

  defp match_vendor?({ "*", "*", _ }, _, formats),
    do: { nil, List.first(formats) }

  defp match_vendor?(_, _, _),
    do: nil
end
