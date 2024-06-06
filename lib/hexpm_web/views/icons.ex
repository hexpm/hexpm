defmodule HexpmWeb.ViewIcons do
  use Phoenix.HTML

  @icons_dir Path.join(__DIR__, "../../../assets/vendor/icons")
  @heroicons_svg Path.join(@icons_dir, "heroicons.svg")

  @external_resource @heroicons_svg

  # :ok = Application.ensure_loaded(:xmerl)
  # {:ok, xmerl_version} = :application.get_key(:xmerl, :vsn)

  # xmerl_version =
  #   xmerl_version
  #   |> List.to_string
  #   |> String.split(".")
  #   |> Enum.concat(["0"])
  #   |> Enum.take(3)
  #   |> Enum.join(".")

  # broken_xmerl? = Version.compare(xmerl_version, "1.3.20") == :lt

  doc = File.read!(@heroicons_svg)

  defp heroicon(title) when is_atom(title), do: heroicon(Atom.to_string(title))

  doc
  |> String.split("\n")
  |> Enum.each(fn line ->
    case Regex.named_captures(~r/\<g title=\"(?<title>[\w\d\-]+)\"/, line) do
      %{"title" => title} -> defp heroicon(unquote(title)), do: unquote(line)
      _ -> :noop
    end
  end)

  # Example return
 #   %{
#   title: ~c"tag",
#   d: [~c"M9.56802 3H5.25C4.00736 3 3 4.00736 3 5.25V9.56802C3 10.1648 3.23705 10.7371 3.65901 11.159L13.2401 20.7401C13.9388 21.4388 15.0199 21.6117 15.8465 21.0705C17.9271 19.7084 19.7084 17.9271 21.0705 15.8465C21.6117 15.0199 21.4388 13.9388 20.7401 13.2401L11.159 3.65901C10.7371 3.23705 10.1648 3 9.56802 3Z",
#    ~c"M6 6H6.0075V6.0075H6V6Z"],
#   stroke: [~c"#0F172A", ~c"#0F172A"]
# }
# This will take the lists pulled from the above operation and reduce them into a single list of tuples
# We should build that zipped list and then reduce to build the final tag
# attrs = Enum.zip_reduce([tag[:d], tag[:stroke], tag[:stroke_width], tag[:stroke_linecap], tag[:stroke_linejoin]], [], fn elem, acc -> [List.to_tuple(elem) | acc] end)
# Maybe this is much easier done by splitting the document by \n, and then using a regex to capture the title of the g tag ang build a keyword list where the key is that title and the value is the entire line
# lines = String.split(doc, "\n")
# Regex.named_captures(~r/\<g title=\"(?<title>[\w\d\-]+)\"/, sample)
# %{"title" => "eye-of-3x3"}


  def icon(type, title, opts \\ [])

  def icon(:heroicon, title, opts) do
    class = "heroicon heroicon-#{title}"
    g_tag = heroicon(title)

    opts =
      opts
      |> Keyword.put_new(:"aria-hidden", "true")
      |> Keyword.put_new(:version, "1.1")
      |> Keyword.put_new(:viewBox, "0 0 1024 1024")
      |> Keyword.put_new(:title, title)
      |> Keyword.update(:class, class, &"#{class} #{&1}")

    content_tag :svg, opts, do: to_string(g_tag)
  end

  def icon(_any, _name, _opts), do: nil
end
