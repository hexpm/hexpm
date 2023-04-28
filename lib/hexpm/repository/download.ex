defmodule Hexpm.Repository.Download do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  schema "downloads" do
    belongs_to :package, Package
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
  end

  defmacrop date_trunc(period, expr) when is_binary(period) do
    query = "date_trunc('#{period}', ?)"

    quote do
      fragment(unquote(query), unquote(expr))
    end
  end

  defmacrop date_trunc_format(period, format, expr)
            when is_binary(period) and is_binary(format) do
    query = "to_char(date_trunc('#{period}', ?), '#{format}')"

    quote do
      fragment(unquote(query), unquote(expr))
    end
  end

  def query_filter(query, filter) do
    case filter do
      :day ->
        from(
          d in query,
          group_by: d.day,
          order_by: d.day,
          select: %Download{
            day: date_trunc_format("day", "YYYY-MM-DD", d.day),
            downloads: sum(d.downloads)
          }
        )

      :month ->
        from(
          d in query,
          group_by: date_trunc("month", d.day),
          order_by: date_trunc("month", d.day),
          select: %Download{
            day: date_trunc_format("month", "YYYY-MM", d.day),
            downloads: sum(d.downloads)
          }
        )
    end
  end

  def since_date(query, date) do
    from(d in query, where: d.day >= ^date)
  end

  def last_day() do
    from(d in Download, select: max(d.day))
  end

  def by_period(package_id, filter) do
    from(d in Download, where: d.package_id == ^package_id)
    |> Download.query_filter(filter)
  end
end
