defmodule Hexpm.PromEx.Plugins.HexpmTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Hexpm

  test "mint success tags keep provider cardinality bounded" do
    assert Hexpm.mint_success_tags(%{provider: "github", package_id: 123}) == %{
             provider: "github"
           }

    assert Hexpm.mint_success_tags(%{}) == %{provider: "unknown"}
  end

  test "mint failure tags surface the error reason" do
    assert Hexpm.mint_failure_tags(%{reason: :token_replayed}) == %{reason: :token_replayed}
    assert Hexpm.mint_failure_tags(%{}) == %{reason: "unknown"}
  end
end
