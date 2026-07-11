defmodule Hexpm.Security.UpdaterTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Security.Advisory
  alias Hexpm.Security.AdvisoryAffectedVersion
  alias Hexpm.Security.AdvisoryReference
  alias Hexpm.Security.Updater

  setup do
    Mox.set_mox_global()
    package = insert(:package, name: "oidcc")
    insert(:release, package: package, version: "3.0.0")
    insert(:release, package: package, version: "3.0.1")
    insert(:release, package: package, version: "3.0.2")
    insert(:release, package: package, version: "3.0.3")
    %{package: package}
  end

  test "fetches and imports the advisory archive" do
    expect(Hexpm.HTTP.Mock, :get, fn url, [], opts ->
      assert url == "https://osv-vulnerabilities.storage.googleapis.com/Hex/all.zip"
      assert opts == [receive_timeout: 60_000]
      {:ok, 200, [], zip_body([])}
    end)

    assert :ok = perform_job(Updater, %{})
  end

  test "returns an error for an unexpected response status" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, [], _opts -> {:ok, 503, [], "unavailable"} end)

    assert {:error, {:unexpected_status, 503}} = perform_job(Updater, %{})
  end

  test "returns an error for a transport failure" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, [], _opts -> {:error, :timeout} end)

    assert {:error, {:request_failed, :timeout}} = perform_job(Updater, %{})
  end

  test "returns an error for a malformed archive" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, [], _opts -> {:ok, 200, [], "not a zip"} end)

    assert {:error, {:invalid_archive, _reason}} = perform_job(Updater, %{})
  end

  defp zip_body(advisories) do
    files =
      Enum.map(advisories, fn advisory ->
        {String.to_charlist("#{advisory["id"]}.json"), Jason.encode!(advisory)}
      end)

    {:ok, {_, zip}} = :zip.create(~c"all.zip", files, [:memory])
    zip
  end

  defp process(advisories) do
    advisories
    |> zip_body()
    |> :zip.unzip([:memory])
    |> elem(1)
    |> Updater.process_advisories()
  end

  test "imports an advisory with cvss, references, aliases, and ranges", %{package: package} do
    advisory = %{
      "id" => "GHSA-1234",
      "summary" => "Test vulnerability",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "aliases" => ["CVE-2024-31209"],
      "severity" => [
        %{"type" => "CVSS_V3", "score" => "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}
      ],
      "references" => [
        %{"type" => "WEB", "url" => "https://example.com/x"}
      ],
      "affected" => [
        %{
          "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
          "ranges" => [
            %{
              "type" => "SEMVER",
              "events" => [%{"introduced" => "3.0.0"}, %{"fixed" => "3.0.2"}]
            }
          ],
          "versions" => ["3.0.0", "3.0.1"]
        }
      ]
    }

    assert :ok = process([advisory])

    advisory =
      Repo.get!(Advisory, "GHSA-1234")
      |> Repo.preload([:references, :affected_versions, :affected_releases])

    assert advisory.summary == "Test vulnerability"
    assert advisory.aliases == ["CVE-2024-31209"]
    assert advisory.cvss_vector == "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"
    assert advisory.cvss_score
    assert advisory.cvss_rating == "critical"
    assert [%AdvisoryReference{url: "https://example.com/x"}] = advisory.references

    assert [%AdvisoryAffectedVersion{requirement: req, package_id: pid}] =
             advisory.affected_versions

    assert pid == package.id
    assert to_string(req) == ">= 3.0.0 and < 3.0.2"

    affected_versions = Enum.map(advisory.affected_releases, &to_string(&1.version))
    assert "3.0.0" in affected_versions
    assert "3.0.1" in affected_versions
    refute "3.0.2" in affected_versions
  end

  test "treats `introduced: 0`-only ranges as all versions", %{package: package} do
    advisory = %{
      "id" => "GHSA-allver",
      "summary" => "All versions affected",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{
          "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
          "ranges" => [
            %{"type" => "SEMVER", "events" => [%{"introduced" => "0"}]}
          ]
        }
      ]
    }

    assert :ok = process([advisory])

    advisory =
      Repo.get!(Advisory, "GHSA-allver")
      |> Repo.preload([:affected_versions, :affected_releases])

    assert [%{requirement: req}] = advisory.affected_versions
    assert to_string(req) == ">= 0.0.0"
    assert length(advisory.affected_releases) == 4
    assert package.id
  end

  test "handles ranges-only entries (no versions array)", %{package: _package} do
    advisory = %{
      "id" => "GHSA-rangesonly",
      "summary" => "Ranges only",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{
          "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
          "ranges" => [
            %{
              "type" => "SEMVER",
              "events" => [%{"introduced" => "3.0.0"}, %{"fixed" => "3.0.2"}]
            }
          ]
        }
      ]
    }

    assert :ok = process([advisory])

    advisory =
      Repo.get!(Advisory, "GHSA-rangesonly")
      |> Repo.preload([:affected_releases])

    affected_versions = Enum.map(advisory.affected_releases, &to_string(&1.version))
    assert "3.0.0" in affected_versions
    assert "3.0.1" in affected_versions
    refute "3.0.2" in affected_versions
  end

  test "ignores non-Hex ecosystem entries" do
    advisory = %{
      "id" => "GHSA-cross",
      "summary" => "Cross ecosystem",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{
          "package" => %{"name" => "lodash", "ecosystem" => "npm"},
          "versions" => ["3.0.0"]
        }
      ]
    }

    assert :ok = process([advisory])
    refute Repo.get(Advisory, "GHSA-cross")
  end

  test "handles multi-Hex-package advisories without cross-pollution" do
    other = insert(:package, name: "ueberauth_oidcc")
    insert(:release, package: other, version: "1.0.0")

    advisory = %{
      "id" => "GHSA-multi",
      "summary" => "Affects two packages",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{
          "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
          "versions" => ["3.0.0"]
        },
        %{
          "package" => %{"name" => "ueberauth_oidcc", "ecosystem" => "Hex"},
          "versions" => ["1.0.0"]
        }
      ]
    }

    assert :ok = process([advisory])

    advisory =
      Repo.get!(Advisory, "GHSA-multi")
      |> Repo.preload([:affected_releases])

    versions = Enum.map(advisory.affected_releases, &to_string(&1.version)) |> Enum.sort()
    assert versions == ["1.0.0", "3.0.0"]
  end

  test "stores withdrawn_at and excludes from public listing", %{package: package} do
    advisory = %{
      "id" => "GHSA-withdrawn",
      "summary" => "Withdrawn",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "withdrawn" => "2024-05-01T00:00:00Z",
      "affected" => [
        %{
          "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
          "versions" => ["3.0.0"]
        }
      ]
    }

    assert :ok = process([advisory])

    advisory = Repo.get!(Advisory, "GHSA-withdrawn")
    assert advisory.withdrawn_at == ~U[2024-05-01 00:00:00Z]

    refute "GHSA-withdrawn" in Enum.map(Hexpm.Security.Advisories.all(package), & &1.id)
  end

  test "tolerates malformed CVSS vectors without dropping the advisory" do
    advisory = %{
      "id" => "GHSA-badcvss",
      "summary" => "Bad CVSS vector",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "severity" => [%{"type" => "CVSS_V3", "score" => "not-a-real-vector"}],
      "affected" => [
        %{
          "package" => %{"name" => "oidcc", "ecosystem" => "Hex"},
          "versions" => ["3.0.0"]
        }
      ]
    }

    assert :ok = process([advisory])

    advisory = Repo.get!(Advisory, "GHSA-badcvss")
    assert advisory.cvss_vector == nil
    assert advisory.cvss_score == nil
    assert advisory.cvss_rating == nil
  end

  test "reconciles by removing advisories absent on subsequent fetches", %{package: package} do
    keep = %{
      "id" => "GHSA-keep",
      "summary" => "Keep",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{"package" => %{"name" => "oidcc", "ecosystem" => "Hex"}, "versions" => ["3.0.0"]}
      ]
    }

    drop = %{
      "id" => "GHSA-drop",
      "summary" => "Drop",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{"package" => %{"name" => "oidcc", "ecosystem" => "Hex"}, "versions" => ["3.0.1"]}
      ]
    }

    assert :ok = process([keep, drop])
    assert Repo.aggregate(Advisory, :count) == 2

    assert :ok = process([keep])
    assert Repo.get(Advisory, "GHSA-keep")
    refute Repo.get(Advisory, "GHSA-drop")
    assert package.id
  end

  test "repeated imports are idempotent" do
    advisory = %{
      "id" => "GHSA-repeat",
      "summary" => "Repeat",
      "modified" => "2024-04-05T01:28:39Z",
      "published" => "2024-04-03T16:46:30Z",
      "affected" => [
        %{"package" => %{"name" => "oidcc", "ecosystem" => "Hex"}, "versions" => ["3.0.0"]}
      ]
    }

    assert :ok = process([advisory])
    assert :ok = process([advisory])
    assert Repo.aggregate(Advisory, :count) == 1
  end
end
