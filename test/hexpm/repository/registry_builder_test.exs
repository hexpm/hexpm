defmodule Hexpm.Repository.RegistryBuilderTest do
  use Hexpm.DataCase

  alias Hexpm.Repository.Release
  alias Hexpm.Repository.RegistryBuilder

  @checksum "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

  setup do
    packages = [p1, p2, p3] = insert_list(3, :package)

    req1 = insert(:requirement, requirement: "0.0.1", dependency: p1, app: p1.name)
    req2 = insert(:requirement, requirement: "~> 0.0.1", dependency: p2, app: p2.name)
    req3 = insert(:requirement, requirement: "0.0.1", dependency: p1, app: p1.name)

    r1 = insert(:release, package: p1, version: "0.0.1")
    r2 = insert(:release, package: p2, version: "0.0.1")
    r3 = insert(:release, package: p2, version: "0.0.2", requirements: [req1])
    r4 = insert(:release, package: p3, version: "0.0.2", requirements: [req2, req3])

    insert(:install, hex: "0.0.1", elixirs: ["1.0.0"])
    insert(:install, hex: "0.1.0", elixirs: ["1.1.0", "1.1.1"])

    %{packages: packages, releases: [r1, r2, r3, r4]}
  end

  defp open_table do
    contents = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", []) |> :zlib.gunzip
    File.write!("tmp/registry_builder_test.ets", contents)
    {:ok, tid} = :ets.file2tab('tmp/registry_builder_test.ets')
    tid
  end

  defp v2_map(path) do
    {module, message} = path_to_protobuf(path)
    if contents = Hexpm.Store.get(nil, :s3_bucket, path, []) do
      %{payload: payload, signature: signature} =
        contents
        |> :zlib.gunzip
        |> :hex_pb_signed.decode_msg(:Signed)

      public_key = Application.fetch_env!(:hexpm, :public_key)
      assert Hexpm.Utils.verify(payload, signature, public_key)
      module.decode_msg(payload, message)
    end
  end

  defp path_to_protobuf("names"), do: {:hex_pb_names, :Names}
  defp path_to_protobuf("versions"), do: {:hex_pb_versions, :Versions}
  defp path_to_protobuf("packages/" <> _), do: {:hex_pb_package, :Package}

  describe "full_build/0" do
    test "registry is versioned" do
      RegistryBuilder.full_build()
      tid = open_table()

      assert [{:"$$version$$", 4}] = :ets.lookup(tid, :"$$version$$")
    end

    test "registry is in correct format", %{packages: [p1, p2, p3]} do
      RegistryBuilder.full_build()
      tid = open_table()

      assert length(:ets.match_object(tid, :_)) == 9
      assert :ets.lookup(tid, p2.name) == [{p2.name, [["0.0.1", "0.0.2"]]}]
      assert :ets.lookup(tid, {p2.name, "0.0.1"}) == [{{p2.name, "0.0.1"}, [[], @checksum, ["mix"]]}]
      assert :ets.lookup(tid, p3.name) == [{p3.name, [["0.0.2"]]}]

      requirements = :ets.lookup(tid, {p3.name, "0.0.2"}) |> List.first |> elem(1) |> List.first
      assert length(requirements ) == 2
      assert Enum.find(requirements, &(&1 == [p2.name, "~> 0.0.1", false, p2.name]))
      assert Enum.find(requirements, &(&1 == [p1.name, "0.0.1", false, p1.name]))

      assert [] = :ets.lookup(tid, "non_existant")
    end

    test "registry is uploaded alongside signature" do
      RegistryBuilder.full_build()

      registry = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", [])
      signature = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz.signed", [])

      public_key = Application.fetch_env!(:hexpm, :public_key)
      signature = Base.decode16!(signature, case: :lower)
      assert Hexpm.Utils.verify(registry, signature, public_key)
    end

    test "registry v2 is in correct format", %{packages: [p1, p2, p3] = packages} do
      RegistryBuilder.full_build()
      first = packages |> Enum.map(& &1.name) |> Enum.sort |> List.first

      names = v2_map("names")
      assert length(names.packages) == 3
      assert List.first(names.packages) == %{name: first}

      versions = v2_map("versions")
      assert length(versions.packages) == 3
      assert Enum.find(versions.packages, &(&1.name == p2.name)) == %{name: p2.name, versions: ["0.0.1", "0.0.2"], retired: []}

      package2 = v2_map("packages/#{p2.name}")
      assert length(package2.releases) == 2
      assert List.first(package2.releases) == %{version: "0.0.1", checksum: Base.decode16!(@checksum), dependencies: []}

      package3 = v2_map("packages/#{p3.name}")
      assert [%{version: "0.0.2", dependencies: deps}] = package3.releases
      assert length(deps) == 2
      assert %{package: p2.name, requirement: "~> 0.0.1"} in deps
      assert %{package: p1.name, requirement: "0.0.1"} in deps
    end

    test "remove package", %{packages: [p1, p2, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.full_build()

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.full_build

      assert length(v2_map("names").packages) == 2
      assert v2_map("packages/#{p1.name}")
      assert v2_map("packages/#{p2.name}")
      refute v2_map("packages/#{p3.name}")
    end
  end

  describe "partial_build/1" do
    test "add release", %{packages: [_, p2, _]} do
      RegistryBuilder.full_build()

      release = insert(:release, package: p2, version: "0.0.3")
      Release.retire(release, %{retirement: %{reason: "invalid", message: "message"}}) |> Hexpm.Repo.update!
      RegistryBuilder.partial_build({:publish, p2.name})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 10

      versions = v2_map("versions")
      assert Enum.find(versions.packages, &(&1.name == p2.name)) == %{name: p2.name, versions: ["0.0.1", "0.0.2", "0.0.3"], retired: [2]}

      package = v2_map("packages/#{p2.name}")
      assert length(package.releases) == 3
      release = List.last(package.releases)
      assert release.version == "0.0.3"
      assert release.retired.reason == :RETIRED_INVALID
      assert release.retired.message == "message"
    end

    test "remove release", %{packages: [_, p2, _], releases: [_, _, r3, _]} do
      RegistryBuilder.full_build()

      Hexpm.Repo.delete!(r3)
      RegistryBuilder.partial_build({:publish, p2.name})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 8

      versions = v2_map("versions")
      assert Enum.find(versions.packages, &(&1.name == p2.name)) == %{name: p2.name, versions: ["0.0.1"], retired: []}

      package2 = v2_map("packages/#{p2.name}")
      assert length(package2.releases) == 1
    end

    test "add package" do
      RegistryBuilder.full_build()

      p = insert(:package)
      insert(:release, package: p, version: "0.0.1")
      RegistryBuilder.partial_build({:publish, p.name})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 11

      assert length(v2_map("names").packages) == 4

      versions = v2_map("versions")
      assert Enum.find(versions.packages, &(&1.name == p.name)) == %{name: p.name, versions: ["0.0.1"], retired: []}

      ecto = v2_map("packages/#{p.name}")
      assert length(ecto.releases) == 1
    end

    test "remove package", %{packages: [_, _, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.full_build()

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.partial_build({:publish, p3.name})

      tid = open_table()
      assert length(:ets.match_object(tid, :_)) == 7

      assert length(v2_map("names").packages) == 2
      assert length(v2_map("versions").packages) == 2

      refute v2_map("packages/#{p3.name}")
    end
  end
end
