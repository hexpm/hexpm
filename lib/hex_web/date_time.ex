defmodule HexWeb.DateTime do
  @behaviour Ecto.Type

  # From Ecto.DateTime

  defmacrop is_date(_year, month, day) do
    quote do
      unquote(month) in 1..12 and unquote(day) in 1..31
    end
  end

  defmacrop is_time(hour, min, sec) do
    quote do
      unquote(hour) in 0..23 and
        unquote(min) in 0..59 and
        unquote(sec) in 0..59
    end
  end

  def type do
    :datetime
  end

  def blank?(term) do
    cast(term) == :error
  end

  def cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep,
             hour::2-bytes, ?:, min::2-bytes, ?:, sec::2-bytes>>) when sep in [?\s, ?T] do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(sec))
  end

  def cast(%Ecto.DateTime{} = dt) do
    {:ok, dt}
  end

  def cast(%{"year" => year, "month" => month, "day" => day, "hour" => hour, "min" => min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, "sec", 0)))
  end

  def cast(%{year: year, month: month, day: day, hour: hour, min: min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, :sec, 0)))
  end

  def cast(_) do
    :error
  end

  def load({{year, month, day}, {hour, min, sec}}) do
    {:ok, %Ecto.DateTime{year: year, month: month, day: day,
                         hour: hour, min: min, sec: sec}}
  end

  def load(nil) do
    {:ok, nil}
  end

  def dump(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    {:ok, {{year, month, day}, {hour, min, sec}}}
  end

  def dump(nil) do
    {:ok, nil}
  end

  defp from_parts(year, month, day, hour, min, sec)
      when is_date(year, month, day) and is_time(hour, min, sec) do
    {:ok, %Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}}
  end
  defp from_parts(_, _, _, _, _, _), do: :error

  defp to_i(nil), do: nil
  defp to_i(int) when is_integer(int), do: int
  defp to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
