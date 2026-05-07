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

  defp record(id, package_name, opts) do
    %{
      id: id,
      summary: opts[:summary] || "summary",
      aliases: opts[:aliases] || [],
      published_at: opts[:published_at] || ~U[2024-04-03 16:46:30Z],
      modified_at: opts[:modified_at] || ~U[2024-04-05 01:28:39Z],
      withdrawn_at: opts[:withdrawn_at],
      cvss_vector: opts[:cvss_vector],
      cvss_score: opts[:cvss_score],
      cvss_rating: opts[:cvss_rating],
      references: opts[:references] || [],
      affected: [
        %{
          package: package_name,
          requirements: opts[:requirements] || [],
          versions: opts[:versions] || []
        }
      ]
    }
  end

  test "upsert inserts new advisories with typed columns and references", %{package: package} do
    record =
      record("GHSA-test-1234-abcd", "oidcc",
        summary: "Test security vulnerability",
        aliases: ["CVE-2024-31209"],
        cvss_vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
        cvss_score: 9.8,
        cvss_rating: "critical",
        references: [%{type: "WEB", url: "https://example.com/advisory"}],
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")],
        versions: ["3.0.0", "3.0.1"]
      )

    assert {:ok, _} = Advisories.upsert([record], %{"oidcc" => package.id})

    advisory =
      Repo.get!(Advisory, "GHSA-test-1234-abcd")
      |> Repo.preload([:references, :affected_versions, :affected_packages])

    assert advisory.summary == "Test security vulnerability"
    assert advisory.aliases == ["CVE-2024-31209"]
    assert advisory.cvss_vector == "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"
    assert advisory.cvss_score == 9.8
    assert advisory.cvss_rating == "critical"
    assert [%{type: "WEB", url: "https://example.com/advisory"}] = advisory.references
    assert [%{requirement: req, package_id: pid}] = advisory.affected_versions
    assert pid == package.id
    assert to_string(req) == ">= 3.0.0 and < 3.0.2"
    assert [%{id: pid}] = advisory.affected_packages
    assert pid == package.id
  end

  test "upsert resolves affected releases via versions", %{
    package: package,
    release_300: release_300,
    release_301: release_301,
    release_302: release_302
  } do
    record = record("GHSA-by-version", "oidcc", versions: ["3.0.0", "3.0.1"])

    assert {:ok, _} = Advisories.upsert([record], %{"oidcc" => package.id})

    affected_ids =
      from(r in Release, join: a in assoc(r, :security_advisories), select: r.id)
      |> Repo.all()

    assert release_300.id in affected_ids
    assert release_301.id in affected_ids
    refute release_302.id in affected_ids
  end

  test "upsert resolves affected releases via ranges only (no versions field)", %{
    package: package,
    release_300: release_300,
    release_301: release_301,
    release_302: release_302
  } do
    record =
      record("GHSA-ranges-only", "oidcc",
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")]
      )

    assert {:ok, _} = Advisories.upsert([record], %{"oidcc" => package.id})

    affected_ids =
      from(r in Release, join: a in assoc(r, :security_advisories), select: r.id)
      |> Repo.all()

    assert release_300.id in affected_ids
    assert release_301.id in affected_ids
    refute release_302.id in affected_ids
  end

  test "upsert updates existing advisory and replaces children", %{package: package} do
    original =
      record("GHSA-test-1234-abcd", "oidcc",
        summary: "Original summary",
        references: [%{type: "WEB", url: "https://old.example.com/"}],
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")]
      )

    assert {:ok, _} = Advisories.upsert([original], %{"oidcc" => package.id})

    updated =
      record("GHSA-test-1234-abcd", "oidcc",
        summary: "Updated summary",
        modified_at: ~U[2024-04-06 00:00:00Z],
        references: [%{type: "WEB", url: "https://new.example.com/"}],
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.3")]
      )

    assert {:ok, _} = Advisories.upsert([updated], %{"oidcc" => package.id})

    advisory =
      Repo.get!(Advisory, "GHSA-test-1234-abcd")
      |> Repo.preload([:references, :affected_versions])

    assert advisory.summary == "Updated summary"
    assert [%{url: "https://new.example.com/"}] = advisory.references
    assert [%{requirement: req}] = advisory.affected_versions
    assert to_string(req) == ">= 3.0.0 and < 3.0.3"
    assert Repo.aggregate(Advisory, :count) == 1
  end

  test "upsert reconciles by deleting advisories absent from the feed", %{package: package} do
    a = record("GHSA-keep", "oidcc", versions: ["3.0.0"])
    b = record("GHSA-drop", "oidcc", versions: ["3.0.1"])

    assert {:ok, _} = Advisories.upsert([a, b], %{"oidcc" => package.id})
    assert Repo.aggregate(Advisory, :count) == 2

    assert {:ok, _} = Advisories.upsert([a], %{"oidcc" => package.id})
    assert Repo.get(Advisory, "GHSA-keep")
    refute Repo.get(Advisory, "GHSA-drop")
  end

  test "upsert handles one advisory affecting multiple Hex packages without collision",
       %{package: oidcc} do
    other = insert(:package, name: "ueberauth_oidcc")
    insert(:release, package: other, version: "3.0.0")

    record = %{
      id: "GHSA-multi",
      summary: "Multi-package advisory",
      aliases: [],
      published_at: ~U[2024-04-03 16:46:30Z],
      modified_at: ~U[2024-04-05 01:28:39Z],
      withdrawn_at: nil,
      cvss_vector: nil,
      cvss_score: nil,
      cvss_rating: nil,
      references: [],
      affected: [
        %{package: "oidcc", requirements: [], versions: ["3.0.0"]},
        %{package: "ueberauth_oidcc", requirements: [], versions: ["3.0.0"]}
      ]
    }

    package_ids = %{"oidcc" => oidcc.id, "ueberauth_oidcc" => other.id}
    assert {:ok, _} = Advisories.upsert([record], package_ids)

    oidcc_advisories = Advisories.all(oidcc)
    other_advisories = Advisories.all(other)

    assert length(oidcc_advisories) == 1
    assert length(other_advisories) == 1
    assert hd(oidcc_advisories).id == "GHSA-multi"
    assert hd(other_advisories).id == "GHSA-multi"
  end

  test "all returns only non-withdrawn advisories", %{package: package} do
    active = record("GHSA-active", "oidcc", versions: ["3.0.0"])

    withdrawn =
      record("GHSA-withdrawn", "oidcc",
        versions: ["3.0.0"],
        withdrawn_at: ~U[2024-05-01 00:00:00Z]
      )

    assert {:ok, _} = Advisories.upsert([active, withdrawn], %{"oidcc" => package.id})

    ids = Advisories.all(package) |> Enum.map(& &1.id)
    assert "GHSA-active" in ids
    refute "GHSA-withdrawn" in ids
  end

  test "all returns advisories for release", %{
    package: package,
    release_300: release_300,
    release_302: release_302
  } do
    record = record("GHSA-rel", "oidcc", versions: ["3.0.0", "3.0.1"])

    assert {:ok, _} = Advisories.upsert([record], %{"oidcc" => package.id})

    assert [%Advisory{id: "GHSA-rel"}] = Advisories.all(release_300)
    assert [] == Advisories.all(release_302)
  end

  test "upsert skips sync for unchanged advisories", %{package: package} do
    record =
      record("GHSA-skip", "oidcc",
        versions: ["3.0.0"],
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")],
        references: [%{type: "WEB", url: "https://example.com/skip"}]
      )

    assert {:ok, %{upsert_advisories: changed}} =
             Advisories.upsert([record], %{"oidcc" => package.id})

    assert Map.has_key?(changed, "GHSA-skip")

    reference_ids = child_keys("security_advisory_references", "GHSA-skip", :id)
    affected_version_ids = child_keys("security_advisory_affected_versions", "GHSA-skip", :id)

    affected_package_links =
      child_keys("security_advisory_affected_packages", "GHSA-skip", :package_id)

    affected_release_links =
      child_keys("security_advisory_affected_releases", "GHSA-skip", :release_id)

    refute reference_ids == []
    refute affected_version_ids == []
    refute affected_package_links == []
    refute affected_release_links == []

    # Second upsert with same modified_at — sync steps must not churn child
    # rows. References/affected_versions keep their primary keys (proves no
    # delete+reinsert); join tables preserve their links.
    assert {:ok, %{upsert_advisories: changed}} =
             Advisories.upsert([record], %{"oidcc" => package.id})

    assert map_size(changed) == 0
    assert child_keys("security_advisory_references", "GHSA-skip", :id) == reference_ids

    assert child_keys("security_advisory_affected_versions", "GHSA-skip", :id) ==
             affected_version_ids

    assert child_keys("security_advisory_affected_packages", "GHSA-skip", :package_id) ==
             affected_package_links

    assert child_keys("security_advisory_affected_releases", "GHSA-skip", :release_id) ==
             affected_release_links
  end

  defp child_keys(table, advisory_id, column) do
    from(r in table,
      where: r.advisory_id == ^advisory_id,
      order_by: field(r, ^column),
      select: field(r, ^column)
    )
    |> Repo.all()
  end

  test "affect_release_with_existing_advisories matches new release against ranges",
       %{package: package} do
    record =
      record("GHSA-future", "oidcc",
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 4.0.0")]
      )

    assert {:ok, _} = Advisories.upsert([record], %{"oidcc" => package.id})

    new_release = insert(:release, package: package, version: "3.5.0")

    {:ok, advisory_ids} =
      Repo.transaction(fn ->
        {:ok, ids} = Advisories.affect_release_with_existing_advisories(Repo, new_release)
        ids
      end)

    assert "GHSA-future" in advisory_ids
    assert [%Advisory{id: "GHSA-future"}] = Advisories.all(new_release)
  end
end
