defmodule HexpmWeb.StaleTest do
  use ExUnit.Case, async: true

  alias Hexpm.Accounts.{KeyPermission, UserHandles}

  alias Hexpm.Repository.{
    Download,
    PackageDownload,
    PackageMetadata,
    ReleaseDownload,
    ReleaseMetadata,
    ReleaseRetirement
  }

  test "timestamp-less schemas use the minimum last-modified time" do
    schemas = [
      %UserHandles{},
      %KeyPermission{},
      %Download{},
      %PackageDownload{},
      %PackageMetadata{},
      %ReleaseDownload{},
      %ReleaseMetadata{},
      %ReleaseRetirement{}
    ]

    for schema <- schemas do
      assert HexpmWeb.Stale.last_modified(schema) == [~N[0000-01-01 00:00:00], []]
    end
  end
end
