defmodule HexpmWeb.SSOView do
  use HexpmWeb, :view

  def session_started(%{inserted_at: inserted_at}), do: on_day(inserted_at)

  def session_last_used(%{last_use: %{used_at: used_at}}) when not is_nil(used_at),
    do: "last reached Hex.pm " <> on_day(used_at)

  def session_last_used(_session), do: "has never reached Hex.pm"

  defp on_day(timestamp), do: "on " <> Calendar.strftime(timestamp, "%B %-d, %Y")
end
