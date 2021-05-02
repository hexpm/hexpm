defmodule Hexpm.Organization.RegistryBuilderTest do
  use Hexpm.DataCase

  alias Hexpm.Repository.{RegistryBuilder, Repository}

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

      names = v2_map("names", ["hexpm"])
      assert length(names) == 3
      name = first.name
      seconds = DateTime.to_unix(first.updated_at)
      assert %{name: ^name, updated_at: %{seconds: ^seconds}} = List.first(names)

      versions = v2_map("versions", ["hexpm"])
      assert length(versions) == 3

      assert Enum.find(versions, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1", "0.0.2"],
               retired: []
             }

      package2_releases = v2_map("packages/#{p2.name}", ["hexpm", p2.name])
      assert length(package2_releases) == 2

      assert List.first(package2_releases) == %{
               version: "0.0.1",
               inner_checksum: Base.decode16!(@checksum),
               outer_checksum: Base.decode16!(@checksum),
               dependencies: []
             }

      package3_releases = v2_map("packages/#{p3.name}", ["hexpm", p3.name])
      assert [%{version: "0.0.2", dependencies: deps}] = package3_releases
      assert length(deps) == 2
      assert %{package: p2.name, requirement: "~> 0.0.1"} in deps
      assert %{package: p1.name, requirement: "0.0.1"} in deps
    end

    test "remove package", %{packages: [p1, p2, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.full(Repository.hexpm())

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.full(Repository.hexpm())

      assert length(v2_map("names", ["hexpm"])) == 2
      assert v2_map("packages/#{p1.name}", ["hexpm", p1.name])
      assert v2_map("packages/#{p2.name}", ["hexpm", p2.name])
      refute v2_map("packages/#{p3.name}", ["hexpm", p3.name])
    end

    test "registry builds for multiple repositories" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id, repository: repository)
      insert(:release, package: package, version: "0.0.1")
      RegistryBuilder.full(repository)

      names = v2_map("repos/#{repository.name}/names", [repository.name])
      assert length(names) == 1

      versions = v2_map("repos/#{repository.name}/versions", [repository.name])
      assert length(versions) == 1

      releases =
        v2_map("repos/#{repository.name}/packages/#{package.name}", [
          repository.name,
          package.name
        ])

      assert length(releases) == 1
    end
  end

  describe "partial/1" do
    test "v2 registry is in correct format", %{packages: [_, p2, _] = packages} do
      RegistryBuilder.repository(Repository.hexpm())
      first = packages |> Enum.sort_by(& &1.name) |> List.first()

      names = v2_map("names", ["hexpm"])
      assert length(names) == 3
      name = first.name
      seconds = DateTime.to_unix(first.updated_at)
      assert %{name: ^name, updated_at: %{seconds: ^seconds}} = List.first(names)

      versions = v2_map("versions", ["hexpm"])
      assert length(versions) == 3

      assert Enum.find(versions, &(&1.name == p2.name)) == %{
               name: p2.name,
               versions: ["0.0.1", "0.0.2"],
               retired: []
             }
    end

    test "remove package", %{packages: [_, _, p3], releases: [_, _, _, r4]} do
      RegistryBuilder.repository(Repository.hexpm())

      Hexpm.Repo.delete!(r4)
      Hexpm.Repo.delete!(p3)
      RegistryBuilder.repository(Repository.hexpm())

      assert length(v2_map("names", ["hexpm"])) == 2
    end

    test "registry builds for multiple repositories" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id, repository: repository)
      insert(:release, package: package, version: "0.0.1")
      RegistryBuilder.repository(repository)

      names = v2_map("repos/#{repository.name}/names", [repository.name])
      assert length(names) == 1

      versions = v2_map("repos/#{repository.name}/versions", [repository.name])
      assert length(versions) == 1
    end
  end

  describe "package/1" do
    test "registry is in correct format", %{packages: [p1, p2, p3]} do
      RegistryBuilder.package(p2)
      RegistryBuilder.package(p3)

      package2_releases = v2_map("packages/#{p2.name}", ["hexpm", p2.name])
      assert length(package2_releases) == 2

      assert List.first(package2_releases) == %{
               version: "0.0.1",
               inner_checksum: Base.decode16!(@checksum),
               outer_checksum: Base.decode16!(@checksum),
               dependencies: []
             }

      package3_releases = v2_map("packages/#{p3.name}", ["hexpm", p3.name])
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
