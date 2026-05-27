defmodule Hexpm.Repository.PackageDependantsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.{Package, PackageDependant, PackageDependants, Packages}

  setup do
    repository = insert(:repository)
    %{repository: repository}
  end

  defp dependant_names(repository, dependency) do
    Package.dependants([repository], dependency, 1, 20, :name, nil)
    |> Repo.all()
    |> Enum.map(& &1.name)
  end

  defp row_count(package_id) do
    Repo.aggregate(
      from(pd in PackageDependant, where: pd.package_id == ^package_id),
      :count
    )
  end

  test "creates rows for the latest release's dependencies", %{repository: repository} do
    dep_a = insert(:package, name: "dep_a", repository_id: repository.id)
    dep_b = insert(:package, name: "dep_b", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    rel = insert(:release, package: dependant, version: "1.0.0")
    insert(:requirement, release: rel, dependency: dep_a, requirement: "~> 1.0")
    insert(:requirement, release: rel, dependency: dep_b, requirement: "~> 1.0")

    {:ok, latest} = PackageDependants.recompute_for_package(Repo, dependant)

    assert latest.version == Version.parse!("1.0.0")
    assert ["dependant"] = dependant_names(repository, dep_a)
    assert ["dependant"] = dependant_names(repository, dep_b)
  end

  test "only the latest release's deps are reflected", %{repository: repository} do
    dep_a = insert(:package, name: "dep_a", repository_id: repository.id)
    dep_b = insert(:package, name: "dep_b", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    old_release = insert(:release, package: dependant, version: "1.0.0")
    insert(:requirement, release: old_release, dependency: dep_a, requirement: "~> 1.0")

    new_release = insert(:release, package: dependant, version: "2.0.0")
    insert(:requirement, release: new_release, dependency: dep_b, requirement: "~> 1.0")

    {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)

    assert [] = dependant_names(repository, dep_a)
    assert ["dependant"] = dependant_names(repository, dep_b)
  end

  test "is idempotent", %{repository: repository} do
    dep = insert(:package, name: "dep", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    rel = insert(:release, package: dependant, version: "1.0.0")
    insert(:requirement, release: rel, dependency: dep, requirement: "~> 1.0")

    {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)
    {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)

    assert row_count(dependant.id) == 1
  end

  test "removes stale rows when the latest release drops a dep", %{repository: repository} do
    dep = insert(:package, name: "dep", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    old_release = insert(:release, package: dependant, version: "1.0.0")
    insert(:requirement, release: old_release, dependency: dep, requirement: "~> 1.0")

    {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)
    assert ["dependant"] = dependant_names(repository, dep)

    insert(:release, package: dependant, version: "2.0.0")

    {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)

    assert [] = dependant_names(repository, dep)
  end

  test "falls back to latest pre-release when no stable release exists", %{
    repository: repository
  } do
    dep_a = insert(:package, name: "dep_a", repository_id: repository.id)
    dep_b = insert(:package, name: "dep_b", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    rc1 = insert(:release, package: dependant, version: "1.0.0-rc.1")
    insert(:requirement, release: rc1, dependency: dep_a, requirement: "~> 1.0")

    rc2 = insert(:release, package: dependant, version: "1.0.0-rc.2")
    insert(:requirement, release: rc2, dependency: dep_b, requirement: "~> 1.0")

    {:ok, latest} = PackageDependants.recompute_for_package(Repo, dependant)

    assert latest.version == Version.parse!("1.0.0-rc.2")
    assert [] = dependant_names(repository, dep_a)
    assert ["dependant"] = dependant_names(repository, dep_b)
  end

  test "prefers latest stable over latest pre-release", %{repository: repository} do
    stable_dep = insert(:package, name: "stable_dep", repository_id: repository.id)
    pre_dep = insert(:package, name: "pre_dep", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    stable = insert(:release, package: dependant, version: "1.0.0")
    insert(:requirement, release: stable, dependency: stable_dep, requirement: "~> 1.0")

    pre = insert(:release, package: dependant, version: "2.0.0-rc.1")
    insert(:requirement, release: pre, dependency: pre_dep, requirement: "~> 1.0")

    {:ok, latest} = PackageDependants.recompute_for_package(Repo, dependant)

    assert latest.version == Version.parse!("1.0.0")
    assert ["dependant"] = dependant_names(repository, stable_dep)
    assert [] = dependant_names(repository, pre_dep)
  end

  test "uses the dependant's repository_id on inserted rows", %{repository: repository} do
    private_repo = insert(:repository)
    dep = insert(:package, name: "dep", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: private_repo.id)

    rel = insert(:release, package: dependant, version: "1.0.0")
    insert(:requirement, release: rel, dependency: dep, requirement: "~> 1.0")

    {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)

    row = Repo.one!(from pd in PackageDependant, where: pd.package_id == ^dependant.id)
    assert row.dependant_repository_id == private_repo.id
  end

  test "returns :ok with nil and deletes rows when package has no releases", %{
    repository: repository
  } do
    dep = insert(:package, name: "dep", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    Repo.insert!(%PackageDependant{
      dependency_id: dep.id,
      package_id: dependant.id,
      dependant_repository_id: repository.id
    })

    {:ok, latest} = PackageDependants.recompute_for_package(Repo, dependant)

    assert latest == nil
    assert row_count(dependant.id) == 0
  end

  describe "dependant_requirements/2" do
    test "returns the requirement from the latest non-retired release", %{repository: repository} do
      dep = insert(:package, name: "dep", repository_id: repository.id)
      dependant = insert(:package, name: "dependant", repository_id: repository.id)

      old_rel = insert(:release, package: dependant, version: "1.0.0")
      insert(:requirement, release: old_rel, dependency: dep, requirement: "~> 1.0")

      new_rel = insert(:release, package: dependant, version: "2.0.0")
      insert(:requirement, release: new_rel, dependency: dep, requirement: "~> 2.0")

      {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)

      requirements = Packages.dependant_requirements([dependant], dep)
      assert requirements[dependant.id] == "~> 2.0"
    end

    test "skips retired releases", %{repository: repository} do
      dep = insert(:package, name: "dep", repository_id: repository.id)
      dependant = insert(:package, name: "dependant", repository_id: repository.id)

      old_rel = insert(:release, package: dependant, version: "1.0.0")
      insert(:requirement, release: old_rel, dependency: dep, requirement: "~> 1.0")

      retired_rel =
        insert(:release,
          package: dependant,
          version: "2.0.0",
          retirement: %{reason: "deprecated", message: "use something else"}
        )

      insert(:requirement, release: retired_rel, dependency: dep, requirement: "~> 2.0")

      {:ok, _} = PackageDependants.recompute_for_package(Repo, dependant)

      requirements = Packages.dependant_requirements([dependant], dep)
      assert requirements[dependant.id] == "~> 1.0"
    end
  end

  test "retired releases still count as latest", %{repository: repository} do
    dep = insert(:package, name: "dep", repository_id: repository.id)
    dependant = insert(:package, name: "dependant", repository_id: repository.id)

    rel =
      insert(:release,
        package: dependant,
        version: "1.0.0",
        retirement: %{reason: "deprecated", message: "no longer supported"}
      )

    insert(:requirement, release: rel, dependency: dep, requirement: "~> 1.0")

    {:ok, latest} = PackageDependants.recompute_for_package(Repo, dependant)

    assert latest.version == Version.parse!("1.0.0")
    assert ["dependant"] = dependant_names(repository, dep)
  end
end
