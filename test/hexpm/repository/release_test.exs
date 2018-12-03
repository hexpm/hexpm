defmodule Hexpm.Repository.ReleaseTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Release

  setup do
    packages =
      insert_list(3, :package)
      |> Hexpm.Repo.preload(:organization)

    %{packages: packages}
  end

  test "create release and get", %{packages: [package, _, _]} do
    package_id = package.id

    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
             Release.build(package, rel_meta(%{version: "0.0.1", app: package.name}), "")
             |> Hexpm.Repo.insert!()

    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
             Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1")

    Release.build(package, rel_meta(%{version: "0.0.2", app: package.name}), "")
    |> Hexpm.Repo.insert!()

    assert [
             %Release{version: %Version{major: 0, minor: 0, patch: 2}},
             %Release{version: %Version{major: 0, minor: 0, patch: 1}}
           ] = Release.all(package) |> Hexpm.Repo.all() |> Release.sort()
  end

  test "create release with deps", %{packages: [package1, package2, package3]} do
    Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "")
    |> Hexpm.Repo.insert!()

    Release.build(package3, rel_meta(%{version: "0.0.2", app: package3.name}), "")
    |> Hexpm.Repo.insert!()

    meta =
      rel_meta(%{
        requirements: [
          %{name: package3.name, app: package3.name, requirement: "~> 0.0.1", optional: false}
        ],
        app: package2.name,
        version: "0.0.1"
      })

    Release.build(package2, meta, "") |> Hexpm.Repo.insert!()

    meta =
      rel_meta(%{
        requirements: [
          %{name: package3.name, app: package3.name, requirement: "~> 0.0.2", optional: false},
          %{name: package2.name, app: package2.name, requirement: "== 0.0.1", optional: false}
        ],
        app: package1.name,
        version: "0.0.1"
      })

    Release.build(package1, meta, "") |> Hexpm.Repo.insert!()

    release =
      assoc(package1, :releases)
      |> Hexpm.Repo.get_by!(version: "0.0.1")
      |> Hexpm.Repo.preload(:requirements)

    package2_id = package2.id
    package3_id = package3.id
    package2_name = package2.name
    package3_name = package3.name

    assert [
             %{
               dependency_id: ^package3_id,
               app: ^package3_name,
               requirement: "~> 0.0.2",
               optional: false
             },
             %{
               dependency_id: ^package2_id,
               app: ^package2_name,
               requirement: "== 0.0.1",
               optional: false
             }
           ] = release.requirements
  end

  test "create release in other repository with deps", %{packages: [_, package2, package3]} do
    organization = insert(:organization)
    package1_repo = insert(:package, organization_id: organization.id)
    package2_repo = insert(:package, organization_id: organization.id, organization: organization)

    Release.build(package1_repo, rel_meta(%{version: "0.0.1", app: package1_repo.name}), "")
    |> Hexpm.Repo.insert!()

    Release.build(package2, rel_meta(%{version: "0.0.1", app: package2.name}), "")
    |> Hexpm.Repo.insert!()

    Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "")
    |> Hexpm.Repo.insert!()

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package1_repo.name,
            repository: organization.name,
            app: package2_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          },
          %{
            name: package2.name,
            repository: "hexpm",
            app: package2.name,
            requirement: "~> 0.0.1",
            optional: false
          },
          %{name: package3.name, app: package3.name, requirement: "~> 0.0.1", optional: false}
        ],
        app: package2_repo.name,
        version: "0.0.1"
      })

    Release.build(package2_repo, meta, "") |> Hexpm.Repo.insert!()

    release =
      assoc(package2_repo, :releases)
      |> Hexpm.Repo.get_by!(version: "0.0.1")
      |> Hexpm.Repo.preload(:requirements)

    package1_repo_id = package1_repo.id
    package2_id = package2.id
    package3_id = package3.id

    assert [
             %{dependency_id: ^package1_repo_id},
             %{dependency_id: ^package2_id},
             %{dependency_id: ^package3_id}
           ] = release.requirements
  end

  test "create release does not allow deps from other repositories", %{packages: [package1, _, _]} do
    organization1 = insert(:organization)
    organization2 = insert(:organization)
    package1_repo = insert(:package, organization_id: organization1.id)
    package2_repo = insert(:package, organization_id: organization2.id)

    package3_repo =
      insert(:package, organization_id: organization2.id, organization: organization2)

    Release.build(package1_repo, rel_meta(%{version: "0.0.1", app: package1_repo.name}), "")
    |> Hexpm.Repo.insert!()

    Release.build(package2_repo, rel_meta(%{version: "0.0.1", app: package2_repo.name}), "")
    |> Hexpm.Repo.insert!()

    package1 = Repo.preload(package1, :organization)

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package1_repo.name,
            repository: organization1.name,
            app: package1_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          }
        ],
        app: package1.name,
        version: "0.0.1"
      })

    assert %{
             requirements: %{
               repository: "dependencies can only belong to public repository \"hexpm\"" <> _
             }
           } = Release.build(package1, meta, "") |> errors_on()

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package2_repo.name,
            repository: organization1.name,
            app: package2_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          }
        ],
        app: package1.name,
        version: "0.0.1"
      })

    assert %{
             requirements: %{
               repository: "dependencies can only belong to public repository \"hexpm\"" <> _
             }
           } = Release.build(package1, meta, "") |> errors_on()

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package1_repo.name,
            repository: "hexpm",
            app: package1_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          }
        ],
        app: package1.name,
        version: "0.0.1"
      })

    assert %{requirements: %{dependency: "package does not exist" <> _}} =
             Release.build(package1, meta, "") |> errors_on()

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package1_repo.name,
            app: package1_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          }
        ],
        app: package1.name,
        version: "0.0.1"
      })

    assert %{requirements: %{dependency: "package does not exist" <> _}} =
             Release.build(package1, meta, "") |> errors_on()

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package2_repo.name,
            repository: "hexpm",
            app: package2_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          }
        ],
        app: package1.name,
        version: "0.0.1"
      })

    assert %{requirements: %{dependency: "package does not exist" <> _}} =
             Release.build(package3_repo, meta, "") |> errors_on()

    meta =
      rel_meta(%{
        requirements: [
          %{
            name: package2_repo.name,
            app: package2_repo.name,
            requirement: "~> 0.0.1",
            optional: false
          }
        ],
        app: package1.name,
        version: "0.0.1"
      })

    assert %{requirements: %{dependency: "package does not exist" <> _}} =
             Release.build(package3_repo, meta, "") |> errors_on()
  end

  test "validate release", %{packages: [_, package2, package3]} do
    Release.build(
      package3,
      rel_meta(%{version: "0.1.0", app: package3.name, requirements: []}),
      ""
    )
    |> Hexpm.Repo.insert!()

    reqs = [%{name: package3.name, app: package3.name, requirement: "~> 0.1", optional: false}]

    Release.build(
      package2,
      rel_meta(%{version: "0.1.0", app: package2.name, requirements: reqs}),
      ""
    )
    |> Hexpm.Repo.insert!()

    meta = %{"version" => "0.1.0", "requirements" => [], "build_tools" => ["mix"]}

    assert %{meta: %{app: "can't be blank"}} =
             Release.build(package3, %{"meta" => meta}, "") |> errors_on()

    meta = %{"app" => package3.name, "version" => "0.1.0", "requirements" => []}

    assert %{meta: %{build_tools: "can't be blank"}} =
             Release.build(package3, %{"meta" => meta}, "") |> errors_on()

    meta = %{
      "app" => package3.name,
      "version" => "0.1.0",
      "requirements" => [],
      "build_tools" => []
    }

    assert %{meta: %{build_tools: "can't be blank"}} =
             Release.build(package3, %{"meta" => meta}, "") |> errors_on()

    meta = %{
      "app" => package3.name,
      "version" => "0.1.0",
      "requirements" => [],
      "build_tools" => ["mix"],
      "elixir" => "== == 0.0.1"
    }

    assert %{meta: %{elixir: "invalid requirement: \"== == 0.0.1\""}} =
             Release.build(package3, %{"meta" => meta}, "") |> errors_on()

    assert %{version: "is invalid SemVer"} =
             Release.build(package2, rel_meta(%{version: "0.1", app: package2.name}), "")
             |> errors_on()

    reqs = [%{name: package3.name, app: package3.name, requirement: "~> fail", optional: false}]

    assert %{requirements: %{requirement: "invalid requirement: \"~> fail\""}} =
             Release.build(
               package2,
               rel_meta(%{version: "0.1.1", app: package2.name, requirements: reqs}),
               ""
             )
             |> errors_on()

    # Disabled because of resolver bug
    # reqs = [%{name: package3.name, app: package3.name, requirement: "~> 1.0", optional: false}]

    # assert %{requirements: "Failed to use" <> _} =
    #          Release.build(
    #            package2,
    #            rel_meta(%{version: "0.1.1", app: package2.name, requirements: reqs}),
    #            ""
    #          )
    #          |> errors_on()
  end

  test "ensure unique build tools", %{packages: [_, _, package3]} do
    changeset =
      Release.build(
        package3,
        rel_meta(%{version: "0.1.0", app: package3.name, build_tools: ["mix", "make", "make"]}),
        ""
      )

    assert changeset.changes.meta.changes.build_tools == ["mix", "make"]
  end

  test "release version is unique", %{packages: [package1, package2, _]} do
    Release.build(package1, rel_meta(%{version: "0.0.1", app: package1.name}), "")
    |> Hexpm.Repo.insert!()

    Release.build(package2, rel_meta(%{version: "0.0.1", app: package2.name}), "")
    |> Hexpm.Repo.insert!()

    assert {:error, %{errors: [version: {"has already been published", _}]}} =
             Release.build(package1, rel_meta(%{version: "0.0.1", app: package1.name}), "")
             |> Hexpm.Repo.insert()
  end

  test "update release", %{packages: [_, package2, package3]} do
    Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "")
    |> Hexpm.Repo.insert!()

    reqs = [%{name: package3.name, app: package3.name, requirement: "~> 0.0.1", optional: false}]

    release =
      Release.build(
        package2,
        rel_meta(%{version: "0.0.1", app: package2.name, requirements: reqs}),
        ""
      )
      |> Hexpm.Repo.insert!()

    params =
      params(%{
        app: package2.name,
        requirements: [
          %{name: package3.name, app: package3.name, requirement: ">= 0.0.1", optional: false}
        ]
      })

    Release.update(%{release | package: package2}, params, "") |> Hexpm.Repo.update!()

    package3_id = package3.id
    package3_name = package3.name

    release =
      assoc(package2, :releases)
      |> Hexpm.Repo.get_by!(version: "0.0.1")
      |> Hexpm.Repo.preload(:requirements)

    assert [
             %{
               dependency_id: ^package3_id,
               app: ^package3_name,
               requirement: ">= 0.0.1",
               optional: false
             }
           ] = release.requirements
  end

  @tag :skip
  test "do not allow pre-release dependencies of stable releases", %{
    packages: [_, package2, package3]
  } do
    Release.build(package3, rel_meta(%{version: "0.0.1-dev", app: package3.name}), "")
    |> Hexpm.Repo.insert!()

    reqs = [
      %{name: package3.name, app: package3.name, requirement: "~> 0.0.1-alpha", optional: false}
    ]

    assert {:error, changeset} =
             Release.build(
               package2,
               rel_meta(%{version: "0.0.1", app: package2.name, requirements: reqs}),
               ""
             )
             |> Hexpm.Repo.insert()

    assert [
             requirement:
               {"invalid requirement: \"~> 0.0.1-alpha\", unstable requirements are not allowed for stable releases",
                []}
           ] = hd(changeset.changes.requirements).errors

    Release.build(
      package2,
      rel_meta(%{version: "0.0.1-dev", app: package2.name, requirements: reqs}),
      ""
    )
    |> Hexpm.Repo.insert!()
  end

  test "delete release", %{packages: [_, package2, package3]} do
    release =
      Release.build(package3, rel_meta(%{version: "0.0.1", app: package3.name}), "")
      |> Hexpm.Repo.insert!()

    Release.delete(release) |> Hexpm.Repo.delete!()
    refute Hexpm.Repo.get_by(assoc(package2, :releases), version: "0.0.1")
  end
end
