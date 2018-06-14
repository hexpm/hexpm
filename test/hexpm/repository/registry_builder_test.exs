defmodule Hexpm.Organization.RegistryBuilderTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.Organization
  alias Hexpm.Repository.{RegistryBuilder, Release}

  @checksum "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

  setup do
    packages =
      [p1, p2, p3] =
      insert_list(3, :package)
      |> Hexpm.Repo.preload(:organization)

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

  defp open_table(repo \\ nil) do
    path = if repo, do: "repos/#{repo}/registry.ets.gz", else: "registry.ets.gz"

    if contents = Hexpm.Store.get(nil, :s3_bucket, path, []) do
      contents = :zlib.gunzip(contents)
      path = Path.join(Application.get_env(:hexpm, :tmp_dir), "registry_builder_test.ets")
      File.write!(path, contents)
      {:ok, tid} = :ets.file2tab(String.to_charlist(path))
      tid
    end
  end

  defp v2_map(path) do
    nonrepo_path = Regex.replace(~r"^repos/\w+/", path, "")

    if contents = Hexpm.Store.get(nil, :s3_bucket, path, []) do
      public_key = Application.fetch_env!(:hexpm, :public_key)
      {:ok, payload} = :hex_registry.decode_and_verify_signed(:zlib.gunzip(contents), public_key)
      path_to_decoder(nonrepo_path).(payload)
    end
  end

  defp path_to_decoder("names"), do: &:hex_registry.decode_names/1
  defp path_to_decoder("versions"), do: &:hex_registry.decode_versions/1
  defp path_to_decoder("packages/" <> _), do: &:hex_registry.decode_package/1

  describe "full_build/0" do
    test "registry is in correct format", %{packages: [p1, p2, p3]} do
      RegistryBuilder.full_build(Organization.hexpm())
      tid = open_table()

      assert :ets.lookup(tid, :"$$version$$") == [{:"$$version$$", 4}]

      assert length(:ets.match_object(tid, :_)) == 9
      assert :ets.lookup(tid, p2.name) == [{p2.name, [["0.0.1", "0.0.2"]]}]

      assert :ets.lookup(tid, {p2.name, "0.0.1"}) == [
               {{p2.name, "0.0.1"}, [[], @checksum, ["mix"]]}
             ]

      assert :ets.lookup(tid, p3.name) == [{p3.name, [["0.0.2"]]}]

      requirements =
        :ets.lookup(tid, {p3.name, "0.0.2"}) |> List.first() |> elem(1) |> List.first()

      assert length(requirements) == 2
      assert Enum.find(requirements, &(&1 == [p2.name, "~> 0.0.1", false, p2.name]))
      assert Enum.find(requirements, &(&1 == [p1.name, "0.0.1", false, p1.name]))

      assert [] = :ets.lookup(tid, "non_existant")
    end

    test "registry is uploaded alongside signature" do
      RegistryBuilder.full_build(Organization.hexpm())

      registry = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", [])
      signature = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz.signed", [])

      public_key = Application.fetch_env!(:hexpm, :public_key)
      signature = Base.decode16!(signature, case: :lower)
      assert :hex_registry.verify(registry, signature, public_key)
    end

    test "registry v2 is in correct format", %{packages: [p1, p2, p3] = packages} do
      RegistryBuilder.full_build(Organization.hexpm())
      first = packages |> Enum.map(& &1.name) |> Enum.sort() |> List.first()

      names = v2_map("names")
      assert length(names.packages) == 3
      assert List.first(names.packages) == %{name: first}

      versions = v2_map("versions")
      assert length(versions.packages) == 3

      assert Enum.find(versions.packages, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1", "0.0.2"],
               retired: []
             }

      package2 = v2_map("packages/#{p2.name}")
      assert length(package2.releases) == 2

      assert List.first(package2.releases) == %{
               version: "0.0.1",
               checksum: Base.decode16!(@checksum),
               dependencies: []
             }

      package3 = v2_map("packages/#{p3.name}")
      assert [%{version: "0.0.2", dependencies: deps}] = package3.releases
      assert length(deps) == 2
      assert %{package: p2.name, requirement: "~> 0.0.1"} in deps
      assert %{package: p1.name, requirement: "0.0.1"} in deps
    end

    test "remove package", %{packages: [p1, p2, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.full_build(Organization.hexpm())

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.full_build(Organization.hexpm())

      assert length(v2_map("names").packages) == 2
      assert v2_map("packages/#{p1.name}")
      assert v2_map("packages/#{p2.name}")
      refute v2_map("packages/#{p3.name}")
    end

    test "registry builds for multiple repositories" do
      organization = insert(:organization)
      package = insert(:package, organization_id: organization.id, organization: organization)
      insert(:release, package: package, version: "0.0.1")
      RegistryBuilder.full_build(organization)

      refute open_table(organization.name)

      names = v2_map("repos/#{organization.name}/names")
      assert length(names.packages) == 1

      assert v2_map("repos/#{organization.name}/packages/#{package.name}")
    end
  end

  describe "partial_build/1" do
    test "add release", %{packages: [_, p2, _]} do
      RegistryBuilder.full_build(Organization.hexpm())

      release = insert(:release, package: p2, version: "0.0.3")

      Release.retire(release, %{retirement: %{reason: "invalid", message: "message"}})
      |> Hexpm.Repo.update!()

      RegistryBuilder.partial_build({:publish, p2})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 10

      versions = v2_map("versions")

      assert Enum.find(versions.packages, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1", "0.0.2", "0.0.3"],
               retired: [2]
             }

      package = v2_map("packages/#{p2.name}")
      assert length(package.releases) == 3
      release = List.last(package.releases)
      assert release.version == "0.0.3"
      assert release.retired.reason == :RETIRED_INVALID
      assert release.retired.message == "message"
    end

    test "remove release", %{packages: [_, p2, _], releases: [_, _, r3, _]} do
      RegistryBuilder.full_build(Organization.hexpm())

      Hexpm.Repo.delete!(r3)
      RegistryBuilder.partial_build({:publish, p2})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 8

      versions = v2_map("versions")

      assert Enum.find(versions.packages, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1"],
               retired: []
             }

      package2 = v2_map("packages/#{p2.name}")
      assert length(package2.releases) == 1
    end

    test "add package" do
      RegistryBuilder.full_build(Organization.hexpm())

      p = insert(:package) |> Hexpm.Repo.preload(:organization)
      insert(:release, package: p, version: "0.0.1")
      RegistryBuilder.partial_build({:publish, p})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 11

      assert length(v2_map("names").packages) == 4

      versions = v2_map("versions")

      assert Enum.find(versions.packages, &(&1.name == p.name)) == %{
               name: p.name,
               versions: ["0.0.1"],
               retired: []
             }

      ecto = v2_map("packages/#{p.name}")
      assert length(ecto.releases) == 1
    end

    test "remove package", %{packages: [_, _, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.full_build(Organization.hexpm())

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.partial_build({:publish, p3})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 7

      assert length(v2_map("names").packages) == 2
      assert length(v2_map("versions").packages) == 2

      refute v2_map("packages/#{p3.name}")
    end

    test "add package for multiple repositories" do
      organization = insert(:organization)
      package1 = insert(:package, organization_id: organization.id, organization: organization)
      insert(:release, package: package1, version: "0.0.1")
      RegistryBuilder.full_build(organization)

      package2 = insert(:package, organization_id: organization.id, organization: organization)
      insert(:release, package: package2, version: "0.0.1")
      RegistryBuilder.partial_build({:publish, package2})

      refute open_table(organization.name)

      names = v2_map("repos/#{organization.name}/names")
      assert length(names.packages) == 2

      assert v2_map("repos/#{organization.name}/packages/#{package1.name}")
      assert v2_map("repos/#{organization.name}/packages/#{package2.name}")
    end
  end
end
