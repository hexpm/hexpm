defmodule HexWeb.ViewHelpers do
  def paginate(page, count, opts) do
    per_page  = opts[:items_per_page]
    max_links = opts[:page_links] # Needs to be odd number

    all_pages    = div(count - 1, per_page) + 1
    middle_links = div(max_links, 2) + 1

    page_links =
      cond do
        page < middle_links ->
          Enum.take(1..max_links, all_pages)
        page > all_pages - middle_links ->
          start =
            if all_pages > middle_links + 1 do
              all_pages - (middle_links + 1)
            else
              1
            end
          Enum.to_list(start..all_pages)
        true ->
          Enum.to_list(page-2..page+2)
      end

    %{prev: page != 1,
      next: page != all_pages,
      page_links: page_links}
  end

  def params(list) do
    Enum.filter(list, fn {_, v} -> present?(v) end)
  end

  def present?(""),  do: false
  def present?(nil), do: false
  def present?(_),   do: true

  def text_length(text, length) when byte_size(text) > length do
    :binary.part(text, 0, length-3) <> "..."
  end

  def text_length(text, _length) do
    text
  end

  @doc """
  Formats a package's release info into a build tools dependency snippet.
  """
  def dep_snippet(_, _, _, nil) do
    ""
  end

  def dep_snippet(:mix, package_name, release) do
    version = snippet_version(:mix, release.version)
    app_name = release.meta.app || package_name

    if package_name == app_name do
      "{:#{package_name}, \"#{version}\"}"
    else
      "{:#{app_name}, \"#{version}\", hex: :#{package_name}}"
    end
  end

  def dep_snippet(:rebar, package_name, release) do
    version = snippet_version(:rebar, release.version)
    app_name = release.meta.app || package_name

    if package_name == app_name do
      "{#{package_name}, \"#{version}\"}"
    else
      "{#{app_name}, \"#{version}\", {pkg, #{package_name}}}"
    end
  end

  def dep_snippet(:erlang_mk, package_name, release) do
    version = snippet_version(:erlang_mk, release.version)
    "dep_#{package_name} = hex #{version}"
  end

  def snippet_version(:mix, %Version{major: 0, minor: minor, patch: patch, pre: []}),
    do: "~> 0.#{minor}.#{patch}"
  def snippet_version(:mix, %Version{major: major, minor: minor, pre: []}),
    do: "~> #{major}.#{minor}"
  def snippet_version(:mix, %Version{major: major, minor: minor, patch: patch, pre: pre}),
    do: "~> #{major}.#{minor}.#{patch}#{pre_snippet(pre)}"

  def snippet_version(other, %Version{major: major, minor: minor, patch: patch, pre: pre})
    when other in [:rebar, :erlang_mk],
    do: "#{major}.#{minor}.#{patch}#{pre_snippet(pre)}"

  defp pre_snippet([]), do: ""
  defp pre_snippet(pre) do
    "-" <>
      Enum.map_join(pre, ".", fn
        int when is_integer(int) -> Integer.to_string(int)
        string when is_binary(string) -> string
      end)
  end

  def human_number_space(string) when is_binary(string) do
    split         = rem(byte_size(string), 3)
    string        = :erlang.binary_to_list(string)
    {first, rest} = Enum.split(string, split)
    rest          = Enum.chunk(rest, 3) |> Enum.map(&[" ", &1])
    IO.iodata_to_binary([first, rest])
  end

  def human_number_space(int) when is_integer(int) do
    human_number_space(Integer.to_string(int))
  end

  def human_relative_time_from_now(date) do
    ts = Ecto.DateTime.to_erl(date) |> :calendar.datetime_to_gregorian_seconds
    diff = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time) - ts
    rel_from_now(:calendar.seconds_to_daystime(diff))
  end

  defp rel_from_now({0, {0, 0, sec}}) when sec < 30,
    do: "about now"
  defp rel_from_now({0, {0, min, _}}) when min < 2,
    do: "1 minute ago"
  defp rel_from_now({0, {0, min, _}}),
    do: "#{min} minutes ago"
  defp rel_from_now({0, {1, _, _}}),
    do: "1 hour ago"
  defp rel_from_now({0, {hour, _, _}}) when hour < 24,
    do: "#{hour} hours ago"
  defp rel_from_now({1, {_, _, _}}),
    do: "1 day ago"
  defp rel_from_now({day, {_, _, _}}) when day < 0,
    do: "about now"
  defp rel_from_now({day, {_, _, _}}),
    do: "#{day} days ago"

  def pretty_date(%Ecto.DateTime{year: year, month: month, day: day}) do
    "#{pretty_month(month)} #{day}, #{year}"
  end

  defp pretty_month(1),  do: "January"
  defp pretty_month(2),  do: "February"
  defp pretty_month(3),  do: "March"
  defp pretty_month(4),  do: "April"
  defp pretty_month(5),  do: "May"
  defp pretty_month(6),  do: "June"
  defp pretty_month(7),  do: "July"
  defp pretty_month(8),  do: "August"
  defp pretty_month(9),  do: "September"
  defp pretty_month(10), do: "October"
  defp pretty_month(11), do: "November"
  defp pretty_month(12), do: "December"
end

defimpl Phoenix.HTML.Safe, for: Version do
  def to_iodata(version), do: String.Chars.Version.to_string(version)
end
