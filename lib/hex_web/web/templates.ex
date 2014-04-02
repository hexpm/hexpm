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
      apply(__MODULE__, :"template_#{var!(page)}", [var!(assigns)])
    end
  end

  defp asset_id do
    @asset_id
  end

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

  @templates [
    main: [:page, :assigns],
    index: [:assigns],
    packages: [:assigns],
    package: [:assigns] ]

  Enum.each(@templates, fn { name, args } ->
    file = Path.join([__DIR__, "templates", "#{name}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args,
                           engine: HexWeb.Web.HTML.Engine)
  end)
end
