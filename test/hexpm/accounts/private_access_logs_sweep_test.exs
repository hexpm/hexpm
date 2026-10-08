defmodule Hexpm.Accounts.PrivateAccessLogsSweepTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.PrivateAccessLogsSweep

  @bucket :access_logs_private_bucket

  test "deletes the lines of names that are no organization or repository" do
    insert(:organization, name: "acme")
    insert(:repository, name: "renamed", organization: build(:organization, name: "now_named"))

    keys = [
      "org=acme/service=fastly_hex/dt=2025-01-01/a.log.gz",
      "org=renamed/service=fastly_hex/dt=2025-01-01/a.log.gz",
      "org=gone/service=fastly_hex/dt=2025-01-01/a.log.gz",
      "org=gone/service=s3_hex/dt=2017-01-01/b.log.gz",
      "org=-/service=-/dt=1970-01-01/empty.log.gz"
    ]

    for key <- keys, do: Hexpm.Store.put(@bucket, key, "LINE", [])

    assert PrivateAccessLogsSweep.run() == 1

    assert Hexpm.Store.list(@bucket, "") |> Enum.sort() == [
             "org=-/service=-/dt=1970-01-01/empty.log.gz",
             "org=acme/service=fastly_hex/dt=2025-01-01/a.log.gz",
             "org=renamed/service=fastly_hex/dt=2025-01-01/a.log.gz"
           ]
  end

  test "deletes nothing when every name belongs to an organization" do
    insert(:organization, name: "acme")
    Hexpm.Store.put(@bucket, "org=acme/service=fastly_hex/dt=2025-01-01/a.log.gz", "LINE", [])

    assert PrivateAccessLogsSweep.run() == 0
    assert Hexpm.Store.list(@bucket, "org=acme/") |> Enum.count() == 1
  end
end
