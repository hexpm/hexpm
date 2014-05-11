defmodule HexWeb.Web.Templates do
  require EEx

  @asset_id :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)

  def render(page, assigns) do
    template_main(page, assigns)
  end

  def safe(value) do
    { :safe, value }
  end

  defmacrop inner do
    quote do
      safe apply(__MODULE__, :"template_#{var!(page)}", [var!(assigns)])
    end
  end

  defp asset_id do
    @asset_id
  end

  @templates [
    main: [:page, :assigns],
    error: [:assigns],
    index: [:assigns],
    packages: [:assigns],
    package: [:assigns],
    docs_usage: [:_],
    docs_publish: [:_],
    docs_tasks: [:_], ]

  Enum.each(@templates, fn { name, args } ->
    name = atom_to_binary(name)
    path = String.replace(name, "_", "/")
    file = Path.join([__DIR__, "templates", "#{path}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args,
                           engine: HexWeb.Web.HTML.Engine)
  end)

  def human_relative_time_from_now(date) do
    ts = date |> Ecto.DateTime.to_erl |> :calendar.datetime_to_gregorian_seconds
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

  defp pretty_date(Ecto.DateTime[year: year, month: month, day: day]) do
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
