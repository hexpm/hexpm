defmodule Hexpm.Repository.Download do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  schema "downloads" do
    belongs_to :package, Package
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
    field :updated_at, :utc_datetime_usec, virtual: true
  end

  defmacrop date_trunc(period, expr) do
    quote do
      fragment("date_trunc(?, ?)", unquote(period), unquote(expr))
    end
  end

  defmacrop date_trunc_format(period, format, expr) do
    quote do
      fragment("to_char(date_trunc(?, ?), ?)", unquote(period), unquote(expr), unquote(format))
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
            downloads: sum(d.downloads),
            updated_at: max(d.day)
          }
        )

      :month ->
        from(
          d in query,
          group_by: date_trunc("month", d.day),
          order_by: date_trunc("month", d.day),
          select: %Download{
            day: date_trunc_format("month", "YYYY-MM", d.day),
            downloads: sum(d.downloads),
            updated_at: max(d.day)
          }
        )

      :all ->
        from(
          d in query,
          select: %Download{
            downloads: sum(d.downloads),
            updated_at: max(d.day)
          }
        )
    end
  end
end
