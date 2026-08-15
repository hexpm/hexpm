defmodule Hexpm.Hexdocs.UtilsTest do
  use ExUnit.Case, async: true

  alias Hexpm.Hexdocs.Utils

  test "latest_version/1 prefers the newest stable version" do
    versions = Enum.map(~w(2.0.0-beta.1 1.2.0 1.1.0), &Version.parse!/1)
    assert Utils.latest_version(versions) == Version.parse!("1.2.0")
  end

  test "latest_version/1 falls back to the newest prerelease" do
    versions = Enum.map(~w(2.0.0-beta.2 2.0.0-beta.1), &Version.parse!/1)
    assert Utils.latest_version(versions) == Version.parse!("2.0.0-beta.2")
  end

  test "latest_version?/3 handles stable, prerelease, and special package versions" do
    stable = Version.parse!("1.0.0")
    older = Version.parse!("0.9.0")
    prerelease = Version.parse!("2.0.0-beta.1")

    assert Utils.latest_version?("package", stable, [older])
    refute Utils.latest_version?("package", prerelease, [stable])
    refute Utils.latest_version?("elixir", "main", [stable])
  end
end
