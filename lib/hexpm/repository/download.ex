defmodule Hexpm.Repository.Download do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  schema "downloads" do
    belongs_to :package, Package
    belongs_to :release, Release
    field :downloads, :integer
    field :day, :date
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

  def downloads_for_last_n_days(query, num_of_days) do
    date_start = Date.add(download_last_day(), -num_of_days)
    from(d in query, where: d.day >= ^date_start)
  end

  # Wait for downloads stats job to run until we switch to today
  def download_last_day() do
    if Time.utc_now().hour >= 2 do
      Date.utc_today()
    else
      Date.add(Date.utc_today(), -1)
    end
  end

  def downloads_by_period(package_id, filter) do
    from(d in Download, where: d.package_id == ^package_id)
    |> Download.query_filter(filter)
  end
end
