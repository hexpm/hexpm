defmodule Hexpm.Repository.ReleaseTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Release

  setup do
    packages = insert_list(3, :package)
    %{packages: packages}
  end

  test "create release and get", %{packages: [package, _, _]} do
    package_id = package.id

    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           Release.build(package, rel_meta(%{version: "0.0.1", app: package.name}), "") |> Hexpm.Repo.insert!
    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1")

    Release.build(package, rel_meta(%{version: "0.0.2", app: package.name}), "") |> Hexpm.Repo.insert!
    assert [%Release{version: %Version{major: 0, minor: 0, patch: 2}},
            %Release{version: %Version{major: 0, minor: 0, patch: 1}}] =
           Release.all(package) |> Hexpm.Repo.all |> Release.sort
  end

  test "create release with deps", %{packages: [package1, package2, package3]} do
    Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "") |> Hexpm.Repo.insert!
    Release.build(package3, rel_meta(%{version: "0.0.2", app: package3.name}), "") |> Hexpm.Repo.insert!

    meta = rel_meta(%{requirements: [%{name: package3.name, app: package3.name, requirement: "~> 0.0.1", optional: false}],
                      app: package2.name, version: "0.0.1"})
    Release.build(package2, meta, "") |> Hexpm.Repo.insert!

    meta = rel_meta(%{requirements: [%{name: package3.name, app: package3.name, requirement: "~> 0.0.2", optional: false}, %{name: package2.name, app: package2.name, requirement: "== 0.0.1", optional: false}],
                      app: package1.name, version: "0.0.1"})
    Release.build(package1, meta, "") |> Hexpm.Repo.insert!

    package2_id = package2.id
    package3_id = package3.id
    package2_name = package2.name
    package3_name = package3.name

    release = Hexpm.Repo.get_by!(assoc(package1, :releases), version: "0.0.1")
              |> Hexpm.Repo.preload(:requirements)
    assert [%{dependency_id: ^package3_id, app: ^package3_name, requirement: "~> 0.0.2", optional: false},
            %{dependency_id: ^package2_id, app: ^package2_name, requirement: "== 0.0.1", optional: false}] =
           release.requirements
  end

  test "validate release", %{packages: [_, package2, package3]} do
    Release.build(package3, rel_meta(%{version: "0.1.0", app: package3.name, requirements: []}), "")
    |> Hexpm.Repo.insert!

    reqs = [%{name: package3.name, app: package3.name, requirement: "~> 0.1", optional: false}]
    Release.build(package2, rel_meta(%{version: "0.1.0", app: package2.name, requirements: reqs}), "")
    |> Hexpm.Repo.insert!

    meta = %{"version" => "0.1.0", "requirements" => [], "build_tools" => ["mix"]}
    assert %{meta: %{app: [{"can't be blank", _}]}} =
           Release.build(package3, %{"meta" => meta}, "")
           |> extract_errors

    meta = %{"app" => package3.name, "version" => "0.1.0", "requirements" => []}
    assert %{meta: %{build_tools: [{"can't be blank", _}]}} =
           Release.build(package3, %{"meta" => meta}, "")
           |> extract_errors

    meta = %{"app" => package3.name, "version" => "0.1.0", "requirements" => [], "build_tools" => []}
    assert %{meta: %{build_tools: [{"can't be blank", _}]}} =
           Release.build(package3, %{"meta" => meta}, "")
           |> extract_errors

    meta = %{"app" => package3.name, "version" => "0.1.0", "requirements" => [], "build_tools" => ["mix"], "elixir" => "== == 0.0.1"}
    assert %{meta: %{elixir: [{"invalid requirement: \"== == 0.0.1\"", _}]}} =
           Release.build(package3, %{"meta" => meta}, "")
           |> extract_errors

    assert %{version: [{"is invalid", _}]} =
           Release.build(package2, rel_meta(%{version: "0.1", app: package2.name}), "")
           |> extract_errors

    reqs = [%{name: package3.name, app: package3.name, requirement: "~> fail", optional: false}]
    assert %{requirements: [%{requirement: [{"invalid requirement: \"~> fail\"", []}]}]} =
           Release.build(package2, rel_meta(%{version: "0.1.1", app: package2.name, requirements: reqs}), "")
           |> extract_errors

    reqs = [%{name: package3.name, app: package3.name, requirement: "~> 1.0", optional: false}]
    errors =
      Release.build(package2, rel_meta(%{version: "0.1.1", app: package2.name, requirements: reqs}), "")
      |> extract_errors
    assert hd(errors[:requirements])[:requirement] == [{~s(Failed to use "#{package3.name}" because\n  mix.exs specifies ~> 1.0\n), []}]
  end

  test "ensure unique build tools", %{packages: [_, _, package3]} do
    changeset = Release.build(package3, rel_meta(%{version: "0.1.0", app: package3.name, build_tools: ["mix", "make", "make"]}), "")
    assert changeset.changes.meta.changes.build_tools == ["mix", "make"]
  end

  test "release version is unique", %{packages: [package1, package2, _]} do
    Release.build(package1, rel_meta(%{version: "0.0.1", app: package1.name}), "") |> Hexpm.Repo.insert!
    Release.build(package2, rel_meta(%{version: "0.0.1", app: package2.name}), "") |> Hexpm.Repo.insert!

    assert {:error, %{errors: [version: {"has already been published", []}]}} =
           Release.build(package1, rel_meta(%{version: "0.0.1", app: package1.name}), "")
           |> Hexpm.Repo.insert
  end

  test "update release", %{packages: [_, package2, package3] } do
    Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "") |> Hexpm.Repo.insert!
    reqs = [%{name: package3.name, app: package3.name, requirement: "~> 0.0.1", optional: false}]
    release = Release.build(package2, rel_meta(%{version: "0.0.1", app: package2.name, requirements: reqs}), "") |> Hexpm.Repo.insert!

    params = params(%{app: package2.name, requirements: [%{name: package3.name, app: package3.name, requirement: ">= 0.0.1", optional: false}]})
    Release.update(release, params, "") |> Hexpm.Repo.update!

    package3_id = package3.id
    package3_name = package3.name

    release = Hexpm.Repo.get_by!(assoc(package2, :releases), version: "0.0.1")
              |> Hexpm.Repo.preload(:requirements)
    assert [%{dependency_id: ^package3_id, app: ^package3_name, requirement: ">= 0.0.1", optional: false}] =
           release.requirements
  end

  test "delete release", %{packages: [_, package2, package3]} do
    release = Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "") |> Hexpm.Repo.insert!
    Release.delete(release) |> Hexpm.Repo.delete!
    refute Hexpm.Repo.get_by(assoc(package2, :releases), version: "0.0.1")
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn err -> err end)
  end
end
