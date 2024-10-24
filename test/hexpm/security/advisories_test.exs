defmodule Hexpm.Security.AdvisoriesTest do
  use Hexpm.DataCase

  alias Hexpm.Security.Advisories
  alias Hexpm.Security.Advisory
  alias Hexpm.Repository.Release

  setup do
    package = insert(:package, name: "oidcc")
    release_300 = insert(:release, package: package, version: "3.0.0")
    release_301 = insert(:release, package: package, version: "3.0.1")
    release_302 = insert(:release, package: package, version: "3.0.2")
    release_303 = insert(:release, package: package, version: "3.0.3")

    %{
      package: package,
      release_300: release_300,
      release_301: release_301,
      release_302: release_302,
      release_303: release_303
    }
  end

  test "upsert inserts new advisories", %{package: package} do
    advisory_attrs = [
      %{
        id: "GHSA-test-1234-abcd",
        package_id: package.id,
        summary: "Test security vulnerability",
        affected: [">= 3.0.0 and < 3.0.2"],
        published_at: ~U[2024-04-03T16:46:30Z],
        modified_at: ~U[2024-04-05T01:28:39Z],
        details: %{
          "id" => "GHSA-test-1234-abcd",
          "summary" => "Test security vulnerability",
          "affected" => [
            %{
              "package" => %{
                "name" => "oidcc",
                "ecosystem" => "Hex"
              },
              "versions" => ["3.0.0", "3.0.1"]
            }
          ]
        }
      }
    ]

    assert :ok = Advisories.upsert(advisory_attrs)

    advisory = Repo.get_by(Advisory, id: "GHSA-test-1234-abcd")
    assert advisory.package_id == package.id
    assert advisory.summary == "Test security vulnerability"
    assert advisory.affected == [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")]
    assert advisory.published_at == ~U[2024-04-03T16:46:30Z]
    assert advisory.modified_at == ~U[2024-04-05T01:28:39Z]
    assert advisory.details["id"] == "GHSA-test-1234-abcd"
  end

  test "upsert updates existing advisories", %{package: package} do
    original_attrs = [
      %{
        id: "GHSA-test-1234-abcd",
        package_id: package.id,
        summary: "Original summary",
        affected: [">= 3.0.0 and < 3.0.2"],
        published_at: ~U[2024-04-03T16:46:30Z],
        modified_at: ~U[2024-04-05T01:28:39Z],
        details: %{
          "id" => "GHSA-test-1234-abcd",
          "affected" => [
            %{
              "package" => %{
                "name" => "oidcc",
                "ecosystem" => "Hex"
              },
              "versions" => ["3.0.0", "3.0.1"]
            }
          ]
        }
      }
    ]

    assert :ok = Advisories.upsert(original_attrs)

    updated_attrs = [
      %{
        id: "GHSA-test-1234-abcd",
        package_id: package.id,
        summary: "Updated summary",
        affected: [">= 3.0.0 and < 3.0.3"],
        published_at: ~U[2024-04-03T16:46:30Z],
        modified_at: ~U[2024-04-06T10:00:00Z],
        details: %{
          "id" => "GHSA-test-1234-abcd",
          "affected" => [
            %{
              "package" => %{
                "name" => "oidcc",
                "ecosystem" => "Hex"
              },
              "versions" => ["3.0.0", "3.0.1", "3.0.2"]
            }
          ]
        }
      }
    ]

    assert :ok = Advisories.upsert(updated_attrs)

    advisories = Repo.all(Advisory)
    assert length(advisories) == 1

    advisory = Repo.get_by(Advisory, id: "GHSA-test-1234-abcd")
    assert advisory.summary == "Updated summary"
    assert advisory.affected == [Version.parse_requirement!(">= 3.0.0 and < 3.0.3")]
    assert advisory.modified_at == ~U[2024-04-06T10:00:00Z]
  end

  test "all returns advisories for package", %{package: package} do
    advisory1_attrs = %{
      id: "GHSA-test-1111-aaaa",
      package_id: package.id,
      summary: "First vulnerability",
      affected: [">= 3.0.0 and < 3.0.2"],
      published_at: ~U[2024-04-03T16:46:30Z],
      modified_at: ~U[2024-04-05T01:28:39Z],
      details: %{
        "affected" => [
          %{
            "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
            "versions" => ["3.0.0", "3.0.1"]
          }
        ]
      }
    }

    advisory2_attrs = %{
      id: "GHSA-test-2222-bbbb",
      package_id: package.id,
      summary: "Second vulnerability",
      affected: [">= 3.0.0 and < 3.0.3"],
      published_at: ~U[2024-05-01T10:00:00Z],
      modified_at: ~U[2024-05-02T10:00:00Z],
      details: %{
        "affected" => [
          %{
            "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
            "versions" => ["3.0.0", "3.0.1", "3.0.2"]
          }
        ]
      }
    }

    assert :ok = Advisories.upsert([advisory1_attrs, advisory2_attrs])

    advisories = Advisories.all(package)
    assert length(advisories) == 2
    assert Enum.any?(advisories, &(&1.id == "GHSA-test-1111-aaaa"))
    assert Enum.any?(advisories, &(&1.id == "GHSA-test-2222-bbbb"))
  end

  test "all returns advisories for release", %{
    package: package,
    release_300: release_300,
    release_302: release_302
  } do
    advisory_attrs = [
      %{
        id: "GHSA-test-1234-abcd",
        package_id: package.id,
        summary: "Test vulnerability affecting 3.0.0 and 3.0.1",
        affected: [">= 3.0.0 and < 3.0.2"],
        published_at: ~U[2024-04-03T16:46:30Z],
        modified_at: ~U[2024-04-05T01:28:39Z],
        details: %{
          "affected" => [
            %{
              "package" => %{
                "name" => "oidcc",
                "ecosystem" => "Hex"
              },
              "versions" => ["3.0.0", "3.0.1"]
            }
          ]
        }
      }
    ]

    assert :ok = Advisories.upsert(advisory_attrs)
    assert :ok = Advisories.refresh_affected_releases()

    release_300_advisories = Advisories.all(release_300)
    assert length(release_300_advisories) == 1
    assert hd(release_300_advisories).id == "GHSA-test-1234-abcd"

    release_302_advisories = Advisories.all(release_302)
    assert length(release_302_advisories) == 0
  end

  test "refresh_affected_releases updates materialized view", %{
    package: package,
    release_300: release_300,
    release_301: release_301,
    release_302: release_302,
    release_303: release_303
  } do
    advisory_attrs = [
      %{
        id: "GHSA-test-1234-abcd",
        package_id: package.id,
        summary: "Affects 3.0.0 and 3.0.1",
        affected: [">= 3.0.0 and < 3.0.2"],
        published_at: ~U[2024-04-03T16:46:30Z],
        modified_at: ~U[2024-04-05T01:28:39Z],
        details: %{
          "affected" => [
            %{
              "package" => %{
                "name" => "oidcc",
                "ecosystem" => "Hex"
              },
              "versions" => ["3.0.0", "3.0.1"]
            }
          ]
        }
      }
    ]

    assert :ok = Advisories.upsert(advisory_attrs)
    assert :ok = Advisories.refresh_affected_releases(false)

    affected_release_ids =
      from(r in Release,
        join: a in assoc(r, :security_advisories),
        where: a.id == "GHSA-test-1234-abcd",
        select: r.id
      )
      |> Repo.all()

    assert release_300.id in affected_release_ids
    assert release_301.id in affected_release_ids
    refute release_302.id in affected_release_ids
    refute release_303.id in affected_release_ids
  end
end
