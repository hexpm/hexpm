defmodule HexpmWeb.BasicAuth do
  @moduledoc false

  @permanent_cutoff ~U[2026-11-01 00:00:00Z]
  @brownout_windows %{
    1 => [{0, 1}, {12, 13}],
    2 => [{5, 6}, {17, 18}],
    3 => [{10, 11}, {22, 23}],
    4 => [{3, 4}, {15, 16}],
    5 => [{8, 9}, {20, 21}],
    6 => [{1, 2}, {13, 14}],
    7 => [{6, 7}, {18, 19}],
    8 => [{0, 2}, {12, 14}],
    9 => [{5, 7}, {17, 19}],
    10 => [{10, 12}, {22, 24}],
    11 => [{3, 5}, {15, 17}],
    12 => [{8, 10}, {20, 22}],
    13 => [{1, 3}, {13, 15}],
    14 => [{6, 8}, {18, 20}],
    15 => [{0, 4}, {12, 16}],
    16 => [{3, 7}, {15, 19}],
    17 => [{6, 10}, {18, 22}],
    18 => [{1, 5}, {13, 17}],
    19 => [{4, 8}, {16, 20}],
    20 => [{7, 11}, {19, 23}],
    21 => [{2, 6}, {14, 18}],
    22 => [{0, 8}, {12, 20}],
    23 => [{3, 11}, {15, 23}],
    24 => [{1, 9}, {13, 21}],
    25 => [{4, 12}, {16, 24}],
    26 => [{2, 10}, {14, 22}],
    27 => [{0, 8}, {12, 20}],
    28 => [{3, 11}, {15, 23}],
    29 => [{0, 10}, {12, 22}],
    30 => [{2, 12}, {14, 24}],
    31 => [{1, 11}, {13, 23}]
  }

  def disabled?(datetime \\ DateTime.utc_now()) do
    datetime = datetime |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)

    cond do
      DateTime.compare(datetime, @permanent_cutoff) != :lt ->
        true

      datetime.year == 2026 and datetime.month == 10 ->
        seconds = datetime.hour * 3600 + datetime.minute * 60 + datetime.second

        Enum.any?(@brownout_windows[datetime.day], fn {first_hour, last_hour} ->
          seconds >= first_hour * 3600 and seconds < last_hour * 3600
        end)

      true ->
        false
    end
  end
end
