defmodule HexWeb.DateTimeUTC do
  @behavior Ecto.Type

  defstruct [:year, :month, :day, :hour, :min, :sec, usec: 0]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :datetime

  @doc """
  Casts the given value to datetime.
  It supports:
    * a binary in the "YYYY-MM-DD HH:MM:SS" format
      (may be separated by T and/or followed by "Z", as in `2014-04-17T14:00:00Z`)
    * a binary in the "YYYY-MM-DD HH:MM:SS.USEC" format
      (may be separated by T and/or followed by "Z", as in `2014-04-17T14:00:00.030Z`)
    * a map with `"year"`, `"month"`,`"day"`, `"hour"`, `"min"` keys
      with `"sec"` and `"usec"` as optional keys and values are integers or binaries
    * a map with `:year`, `:month`,`:day`, `:hour`, `:min` keys
      with `:sec` and `:usec` as optional keys and values are integers or binaries
    * a tuple with `{{year, month, day}, {hour, min, sec}}` as integers or binaries
    * a tuple with `{{year, month, day}, {hour, min, sec, usec}}` as integers or binaries
    * an `Ecto.DateTime` struct
    * a `HexWeb.DateTimeUTC itself
  """
  def cast(%HexWeb.DateTimeUTC{} = datetime), do: {:ok, datetime} |> Ecto.DateTime.valid_date?
  def cast(value) do
    case Ecto.DateTime.cast(value) do
      {:ok, datetime} -> {:ok, datetime_to_datetime_utc(datetime)}
      error -> error
    end
  end

  @doc """
  Same as `cast/1` but raises on invalid datetimes.
  """
  def cast!(value) do
    case cast(value) do
      {:ok, datetime} -> datetime
      :error -> raise ArgumentError, "cannot cast #{inspect value} to datetime"
    end
  end

  @doc """
  Converts a `HexWeb.DateTimeUTC` into a `{date, time}` tuple.
  """
  def dump(%HexWeb.DateTimeUTC{} = datetime_utc),
    do: datetime_utc |> datetime_utc_to_datetime |> Ecto.DateTime.dump

  def load(value) do
    case Ecto.DateTime.load(value) do
      {:ok, datetime} -> {:ok, datetime_to_datetime_utc(datetime)}
      error -> error
    end
  end

  @doc """
  Converts `HexWeb.DateTimeUTC` to its string representation.
  """
  def to_string(%HexWeb.DateTimeUTC{} = datetime_utc) do
    to_iso8601(datetime_utc)
  end

  @doc """
  Converts `HexWeb.DateTimeUTC` to its ISO 8601 representation
  with timezone specification.
  """
  def to_iso8601(%HexWeb.DateTimeUTC{} = datetime_utc) do
    Ecto.DateTime.to_iso8601(datetime_utc) <> "Z"
  end

  # Callback invoked by autogenerate fields.
  @doc false
  def autogenerate(precision \\ :sec), do: precision |> Ecto.DateTime.autogenerate |> datetime_to_datetime_utc

  defp datetime_to_datetime_utc(%Ecto.DateTime{} = datetime), do: %{datetime | __struct__: HexWeb.DateTimeUTC}

  defp datetime_utc_to_datetime(%HexWeb.DateTimeUTC{} = datetime_utc), do: %{datetime_utc | __struct__: Ecto.DateTime}
end

defimpl String.Chars, for: HexWeb.DateTimeUTC do
  def to_string(datetime_utc) do
    @for.to_string(datetime_utc)
  end
end

defimpl Inspect, for: HexWeb.DateTimeUTC do
  @inspected inspect(@for)

  def inspect(datetime_utc, _opts) do
    "#" <> @inspected <> "<" <> @for.to_string(datetime_utc) <> ">"
  end
end
