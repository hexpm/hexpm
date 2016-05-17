defmodule HexWeb.EctoPoisonDateTimeOverrideTest do
  use ExUnit.Case

  test "Ecto.DateTime is encoded with a UTC time zone" do
    datetime = Ecto.DateTime.from_erl({{2016, 5, 16}, {11, 3, 33}})

    assert Poison.encode!(datetime) == "\"2016-05-16T11:03:33Z\""
  end
end
