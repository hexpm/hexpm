defmodule HexpmWeb.Session.JSONTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Session.JSON, as: SessionJSON

  test "round trips JSON-compatible session data" do
    assert {:ok, encoded} = SessionJSON.encode(%{foo: "bar"})
    assert {:ok, %{"foo" => "bar"}} = SessionJSON.decode(encoded)
  end

  test "rejects values that cannot be encoded or decoded" do
    assert :error = SessionJSON.encode(self())
    assert :error = SessionJSON.decode("not-json")
  end
end
