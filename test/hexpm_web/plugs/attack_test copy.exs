defmodule HexpmWeb.ErlangFormatTest do
  use ExUnit.Case, async: true
  import HexpmWeb.ErlangFormat

  test "decode/1" do
    long_binary = IO.iodata_to_binary(Enum.map(1..1000, fn _ -> "foobar" end))

    assert decode(:erlang.term_to_binary("foobar")) == {:ok, "foobar"}
    assert decode(long_binary) == {:ok, long_binary}

    assert {:error, _} = decode(:erlang.term_to_binary(fn -> :ok end))
    assert {:error, _} = decode(:erlang.term_to_binary(long_binary, compressed: 9))
    assert {:error, _} = decode(:erlang.term_to_binary(long_binary, compressed: 1))
  end
end
