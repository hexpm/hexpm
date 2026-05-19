defmodule Hexpm.Organization.RegistryBuilderTest do
  use Hexpm.DataCase

  alias Hexpm.Repository.{RegistryBuilder, Repository}
  alias Hexpm.Security.Advisories

  @checksum "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

  setup do
    packages =
      [p1, p2, p3] =
      insert_list(3, :package)
      |> Hexpm.Repo.preload(:repository)

    r1 = insert(:release, package: p1, version: "0.0.1")
    r2 = insert(:release, package: p2, version: "0.0.1")
    r3 = insert(:release, package: p2, version: "0.0.2")
    r4 = insert(:release, package: p3, version: "0.0.2")

    insert(:requirement, release: r3, requirement: "0.0.1", dependency: p1, app: p1.name)
    insert(:requirement, release: r4, requirement: "~> 0.0.1", dependency: p2, app: p2.name)
    insert(:requirement, release: r4, requirement: "0.0.1", dependency: p1, app: p1.name)

    insert(:install, hex: "0.0.1", elixirs: ["1.0.0"])
    insert(:install, hex: "0.1.0", elixirs: ["1.1.0", "1.1.1"])

    %{packages: packages, releases: [r1, r2, r3, r4]}
  end

  defp v2_map(path, args) when is_list(args) do
    nonrepo_path = Regex.replace(~r"^repos/\w+/", path, "")

    if contents = Hexpm.Store.get(:repo_bucket, path, []) do
      public_key = Application.fetch_env!(:hexpm, :public_key)
      {:ok, payload} = :hex_registry.decode_and_verify_signed(:zlib.gunzip(contents), public_key)
      fun = path_to_decoder(nonrepo_path)
      {:ok, decoded} = apply(fun, [payload | args])
      decoded
    end
  end

  defp path_to_decoder("names"), do: &:hex_registry.decode_names/2
  defp path_to_decoder("versions"), do: &:hex_registry.decode_versions/2
  defp path_to_decoder("packages/" <> _), do: &:hex_registry.decode_package/3

  describe "full/0" do
    test "registry is in correct format", %{packages: [p1, p2, p3] = packages} do
      RegistryBuilder.full(Repository.hexpm())
      first = packages |> Enum.sort_by(& &1.name) |> List.first()

      names = v2_map("names", ["hexpm"]).packages
      assert length(names) == 3
      name = first.name
      seconds = DateTime.to_unix(first.updated_at)
      assert %{name: ^name, updated_at: %{seconds: ^seconds}} = List.first(names)

      versions = v2_map("versions", ["hexpm"]).packages
      assert length(versions) == 3

      assert Enum.find(versions, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1", "0.0.2"],
               retired: [],
               with_advisories: []
             }

      package2_releases = v2_map("packages/#{p2.name}", ["hexpm", p2.name]).releases
      assert length(package2_releases) == 2

      assert %{
               version: "0.0.1",
               inner_checksum: inner,
               outer_checksum: outer,
               dependencies: [],
               advisory_indexes: [],
               published_at: %{seconds: seconds, nanos: nanos}
             } = List.first(package2_releases)

      assert inner == Base.decode16!(@checksum)
      assert outer == Base.decode16!(@checksum)
      assert is_integer(seconds) and seconds > 0
      assert is_integer(nanos) and nanos >= 0

      package3_releases = v2_map("packages/#{p3.name}", ["hexpm", p3.name]).releases
      assert [%{version: "0.0.2", dependencies: deps}] = package3_releases
      assert length(deps) == 2
      assert %{package: p2.name, requirement: "~> 0.0.1"} in deps
      assert %{package: p1.name, requirement: "0.0.1"} in deps
    end

    test "published_at matches release inserted_at", %{
      packages: [_, p2, _],
      releases: [_, r2, _, _]
    } do
      RegistryBuilder.full(Repository.hexpm())

      package2 = v2_map("packages/#{p2.name}", ["hexpm", p2.name])
      release = Enum.find(package2.releases, &(&1.version == "0.0.1"))

      unix_ns = DateTime.to_unix(r2.inserted_at, :nanosecond)
      expected_seconds = div(unix_ns, 1_000_000_000)
      expected_nanos = rem(unix_ns, 1_000_000_000)

      assert release.published_at == %{seconds: expected_seconds, nanos: expected_nanos}
    end

    test "advisories are included in registry", %{
      packages: [p1, p2, _p3],
      releases: [r1, _r2, _r3, _r4]
    } do
      assert {:ok, _} =
               Advisories.upsert(
                 [
                   %{
                     id: "GHSA-test-1234-abcd",
                     summary: "Test vulnerability",
                     aliases: [],
                     published_at: ~U[2024-04-03 16:46:30Z],
                     modified_at: ~U[2024-04-05 01:28:39Z],
                     withdrawn_at: nil,
                     cvss_vector: nil,
                     cvss_score: nil,
                     cvss_rating: "high",
                     references: [],
                     affected: [
                       %{
                         package: p1.name,
                         requirements: [],
                         versions: [to_string(r1.version)]
                       }
                     ]
                   }
                 ],
                 %{p1.name => p1.id}
               )

      RegistryBuilder.full(Repository.hexpm())

      versions = v2_map("versions", ["hexpm"]).packages

      assert %{with_advisories: [0]} = Enum.find(versions, &(&1.name == p1.name))
      assert %{with_advisories: []} = Enum.find(versions, &(&1.name == p2.name))

      package1 = v2_map("packages/#{p1.name}", ["hexpm", p1.name])

      assert [
               %{
                 id: "GHSA-test-1234-abcd",
                 summary: "Test vulnerability",
                 severity: :SEVERITY_HIGH
               } = advisory
             ] =
               package1.advisories

      assert String.starts_with?(advisory.html_url, "https://osv.dev/vulnerability/")
      assert String.starts_with?(advisory.api_url, "https://api.osv.dev/v1/vulns/")

      assert [%{advisory_indexes: [0]}] = package1.releases

      package2 = v2_map("packages/#{p2.name}", ["hexpm", p2.name])
      assert package2.advisories == []
      assert Enum.all?(package2.releases, &(&1.advisory_indexes == []))
    end

    test "build_advisory emits aliases, published_at, modified_at, references", %{
      packages: [p1, _, _],
      releases: [r1, _, _, _]
    } do
      published_at = ~U[2026-01-10 12:00:00Z]
      modified_at = ~U[2026-02-15 08:30:00Z]

      assert {:ok, _} =
               Advisories.upsert(
                 [
                   %{
                     id: "GHSA-fields-test-abcd",
                     summary: "Test fields advisory",
                     aliases: ["CVE-2026-0001"],
                     published_at: published_at,
                     modified_at: modified_at,
                     withdrawn_at: nil,
                     cvss_vector: nil,
                     cvss_score: nil,
                     cvss_rating: nil,
                     references: [%{type: "WEB", url: "https://example.com/a"}],
                     affected: [
                       %{
                         package: p1.name,
                         requirements: [],
                         versions: [to_string(r1.version)]
                       }
                     ]
                   }
                 ],
                 %{p1.name => p1.id}
               )

      RegistryBuilder.full(Repository.hexpm())

      package1 = v2_map("packages/#{p1.name}", ["hexpm", p1.name])

      assert [advisory] = package1.advisories
      assert advisory.aliases == ["CVE-2026-0001"]

      assert advisory.published_at == %{seconds: DateTime.to_unix(published_at), nanos: 0}
      assert advisory.modified_at == %{seconds: DateTime.to_unix(modified_at), nanos: 0}

      assert advisory.references == [%{type: "WEB", url: "https://example.com/a"}]
    end

    test "withdrawn advisories are not included in registry", %{
      packages: [p1, _, _],
      releases: [r1, _, _, _]
    } do
      assert {:ok, _} =
               Advisories.upsert(
                 [
                   %{
                     id: "GHSA-withdrawn-1234",
                     summary: "Withdrawn vulnerability",
                     aliases: [],
                     published_at: ~U[2024-04-03 16:46:30Z],
                     modified_at: ~U[2024-04-05 01:28:39Z],
                     withdrawn_at: ~U[2024-04-06 00:00:00Z],
                     cvss_vector: nil,
                     cvss_score: nil,
                     cvss_rating: nil,
                     references: [],
                     affected: [
                       %{
                         package: p1.name,
                         requirements: [],
                         versions: [to_string(r1.version)]
                       }
                     ]
                   }
                 ],
                 %{p1.name => p1.id}
               )

      RegistryBuilder.full(Repository.hexpm())

      versions = v2_map("versions", ["hexpm"]).packages
      assert %{with_advisories: []} = Enum.find(versions, &(&1.name == p1.name))

      package1 = v2_map("packages/#{p1.name}", ["hexpm", p1.name])
      assert package1.advisories == []
      assert [%{advisory_indexes: []}] = package1.releases
    end

    test "remove package", %{packages: [p1, p2, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.full(Repository.hexpm())

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.full(Repository.hexpm())

      assert length(v2_map("names", ["hexpm"]).packages) == 2
      assert v2_map("packages/#{p1.name}", ["hexpm", p1.name])
      assert v2_map("packages/#{p2.name}", ["hexpm", p2.name])
      refute v2_map("packages/#{p3.name}", ["hexpm", p3.name])
    end

    test "registry builds for multiple repositories" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id, repository: repository)
      insert(:release, package: package, version: "0.0.1")
      RegistryBuilder.full(repository)

      names = v2_map("repos/#{repository.name}/names", [repository.name]).packages
      assert length(names) == 1

      versions = v2_map("repos/#{repository.name}/versions", [repository.name]).packages
      assert length(versions) == 1

      releases =
        v2_map("repos/#{repository.name}/packages/#{package.name}", [
          repository.name,
          package.name
        ]).releases

      assert length(releases) == 1
    end
  end

  describe "partial/1" do
    test "v2 registry is in correct format", %{packages: [_, p2, _] = packages} do
      RegistryBuilder.repository(Repository.hexpm())
      first = packages |> Enum.sort_by(& &1.name) |> List.first()

      names = v2_map("names", ["hexpm"]).packages
      assert length(names) == 3
      name = first.name
      seconds = DateTime.to_unix(first.updated_at)
      assert %{name: ^name, updated_at: %{seconds: ^seconds}} = List.first(names)

      versions = v2_map("versions", ["hexpm"]).packages
      assert length(versions) == 3

      assert Enum.find(versions, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1", "0.0.2"],
               retired: [],
               with_advisories: []
             }
    end

    test "remove package", %{packages: [_, _, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.repository(Repository.hexpm())

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.repository(Repository.hexpm())

      assert length(v2_map("names", ["hexpm"]).packages) == 2
    end

    test "registry builds for multiple repositories" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id, repository: repository)
      insert(:release, package: package, version: "0.0.1")
      RegistryBuilder.repository(repository)

      names = v2_map("repos/#{repository.name}/names", [repository.name]).packages
      assert length(names) == 1

      versions = v2_map("repos/#{repository.name}/versions", [repository.name]).packages
      assert length(versions) == 1
    end
  end

  describe "package/1" do
    test "registry is in correct format", %{packages: [p1, p2, p3]} do
      RegistryBuilder.package(p2)
      RegistryBuilder.package(p3)

      package2_releases = v2_map("packages/#{p2.name}", ["hexpm", p2.name]).releases
      assert length(package2_releases) == 2

      assert %{
               version: "0.0.1",
               inner_checksum: inner,
               outer_checksum: outer,
               dependencies: [],
               advisory_indexes: [],
               published_at: %{seconds: seconds, nanos: nanos}
             } = List.first(package2_releases)

      assert inner == Base.decode16!(@checksum)
      assert outer == Base.decode16!(@checksum)
      assert is_integer(seconds) and seconds > 0
      assert is_integer(nanos) and nanos >= 0

      package3_releases = v2_map("packages/#{p3.name}", ["hexpm", p3.name]).releases
      assert [%{version: "0.0.2", dependencies: deps}] = package3_releases
      assert length(deps) == 2
      assert %{package: p2.name, requirement: "~> 0.0.1"} in deps
      assert %{package: p1.name, requirement: "0.0.1"} in deps
    end
  end

  describe "package_delete/1" do
    test "remove package", %{packages: [_, _, p3]} do
      RegistryBuilder.full(Repository.hexpm())
      assert v2_map("packages/#{p3.name}", ["hexpm", p3.name])

      RegistryBuilder.package_delete(p3)
      refute v2_map("packages/#{p3.name}", ["hexpm", p3.name])
    end
  end
end
