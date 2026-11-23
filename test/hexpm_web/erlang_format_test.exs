defmodule HexpmWeb.ErlangFormatTest do
  use ExUnit.Case, async: true
  import HexpmWeb.ErlangFormat

  test "decode/1" do
    long_binary = IO.iodata_to_binary(Enum.map(1..1000, fn _ -> "foobar" end))

    assert decode("") == {:ok, nil}
    assert decode(:erlang.term_to_binary("foobar")) == {:ok, "foobar"}
    assert decode(:erlang.term_to_binary(long_binary)) == {:ok, long_binary}

    assert {:error, _} = decode(:erlang.term_to_binary(fn -> :ok end))
    assert {:error, _} = decode(:erlang.term_to_binary(long_binary, compressed: 9))
    assert {:error, _} = decode(:erlang.term_to_binary(long_binary, compressed: 1))
  end

  test "decode/1 refuses structs" do
    struct = %{__struct__: URI, host: "example.com"}

    assert {:error, _} = decode(:erlang.term_to_binary(struct))
    assert {:error, _} = decode(:erlang.term_to_binary(%{"params" => [{:ok, struct}]}))
    assert {:error, _} = decode(:erlang.term_to_binary(%{struct => "value"}))
    assert {:error, _} = decode(:erlang.term_to_binary([:a | struct]))

    assert decode(
             :erlang.term_to_binary(%{"name" => "foo", "meta" => %{"key" => [1, {:a, "b"}]}})
           ) ==
             {:ok, %{"name" => "foo", "meta" => %{"key" => [1, {:a, "b"}]}}}
  end
end
