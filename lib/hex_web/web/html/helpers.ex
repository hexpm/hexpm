defmodule HexWeb.Web.HTML.Helpers do
  alias HexWeb.Web.HTML.Safe

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

    if page != 1,         do: prev = true
    if page != all_pages, do: next = true

    %{prev: prev || false,
      next: next || false,
      page_links: page_links}
  end

  def url_params([]) do
    ""
  end

  def url_params(list) do
    list = Enum.filter(list, fn {_, v} -> present?(v) end)
    "?" <> Enum.map_join(list, "&", fn {k, v} -> "#{k}=#{v}" end)
  end

  def present?(""),  do: false
  def present?(nil), do: false
  def present?(_),   do: true

  def paragraphize(contents) do
    paragraphs =
      contents
      |> Safe.to_string
      |> :binary.replace("\r", "")
      |> String.replace(~r"(\n{2,})", "</p>\\1<p>")

    {:safe, "<p>" <> paragraphs <> "</p>"}
  end

  def text_length(text, length) when byte_size(text) > length do
    :binary.part(text, 0, length-3) <> "..."
  end

  def text_length(text, _length) do
    text
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
