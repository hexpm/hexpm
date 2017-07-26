import Hexpm.Factory

alias Hexpm.Repository.{PackageDependant, PackageDownload, ReleaseDownload}

Hexpm.Fake.start()

lorem = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

password = &Comeonin.Bcrypt.hashpwsalt/1

Hexpm.Repo.transaction(fn ->
  eric = insert(:user, username: "eric", emails: [build(:email, email: "eric@example.com")], password: password.("ericric"))
  jose = insert(:user, username: "jose", emails: [build(:email, email: "jose@example.com")], password: password.("josejose"))
  joe = insert(:user, username: "joe", emails: [build(:email, email: "joe@example.com")], password: password.("joejoejoe"))
  justin = insert(:user, username: "justin", emails: [build(:email, email: "justin@example.com")], password: password.("justinjustin"))

  decimal = insert(:package,
    name: "decimal",
    package_owners: [build(:package_owner, owner: eric)],
    meta: build(:package_metadata,
      maintainers: ["Eric Meadows-Jönsson"],
      licenses: ["Apache 2.0", "MIT"],
      links: %{"Github" => "http://example.com/github", "Documentation" => "http://example.com/documentation"},
      description: "Arbitrary precision decimal arithmetic for Elixir"))

  insert(:release,
    package: decimal,
    version: "0.0.1",
    meta: build(:release_metadata,
      app: "decimal",
      build_tools: ["mix"]))

  insert(:release,
    package: decimal,
    version: "0.0.2",
    meta: build(:release_metadata,
      app: "decimal",
      build_tools: ["mix"]))

  insert(:release,
    package: decimal,
    version: "0.1.0",
    meta: build(:release_metadata,
      app: "decimal",
      build_tools: ["mix"]))

  postgrex = insert(:package,
    name: "postgrex",
    package_owners: [build(:package_owner, owner: eric), build(:package_owner, owner: jose)],
    meta: build(:package_metadata,
      maintainers: ["Eric Meadows-Jönsson", "José Valim"],
      licenses: ["Apache 2.0"],
      links: %{"Github" => "http://example.com/github"},
      description: lorem))

  insert(:release,
    package: postgrex,
    version: "0.0.1",
    meta: build(:release_metadata,
      app: "postgrex",
      build_tools: ["mix"]))

  insert(:release,
    package: postgrex,
    version: "0.0.2",
    requirements: [build(:requirement,
      dependency: decimal,
      app: "decimal",
      requirement: "~> 0.0.1")],
    meta: build(:release_metadata,
      app: "postgrex",
      build_tools: ["mix"]),
    has_docs: true)

  insert(:release,
    package: postgrex,
    version: "0.1.0",
    requirements: [build(:requirement,
      dependency: decimal,
      app: "decimal",
      requirement: "0.1.0")],
    meta: build(:release_metadata,
      app: "postgrex",
      build_tools: ["mix"]))

  ecto = insert(:package,
    name: "ecto",
    package_owners: [build(:package_owner, owner: jose)],
    meta: build(:package_metadata,
      maintainers: ["Eric Meadows-Jönsson", "José Valim"],
      licenses: [],
      links: %{"Github" => "http://example.com/github"},
      description: lorem))

  insert(:release,
    package: ecto,
    version: "0.0.1",
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]))

  insert(:release,
    package: ecto,
    version: "0.0.2",
    requirements: [build(:requirement,
      dependency: postgrex,
      app: "postgrex",
      requirement: "~> 0.0.1")],
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]))

  insert(:release,
    package: ecto,
    version: "0.1.0",
    requirements: [build(:requirement,
      dependency: postgrex,
      app: "postgrex",
      requirement: "~> 0.0.2")],
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]))

  insert(:release,
    package: ecto,
    version: "0.1.1",
    requirements: [build(:requirement,
      dependency: postgrex,
      app: "postgrex",
      requirement: "~> 0.1.0")],
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]))

  insert(:release,
    package: ecto,
    version: "0.1.2",
    requirements: [
      build(:requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "== 0.1.0"),
      build(:requirement,
        dependency: decimal,
        app: "decimal",
        requirement: "0.1.0")],
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]))

  insert(:release,
    package: ecto,
    version: "0.1.3",
    requirements: [
      build(:requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "0.1.0"),
      build(:requirement,
        dependency: decimal,
        app: "decimal",
        requirement: "0.1.0")],
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]))

  rel = insert(:release,
    package: ecto,
    version: "0.2.0",
    requirements: [
      build(:requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "~> 0.1.0"),
      build(:requirement,
        dependency: decimal,
        app: "decimal",
        requirement: "~> 0.1.0")],
    meta: build(:release_metadata,
      app: "ecto",
      build_tools: ["mix"]),
    has_docs: true)

  insert(:download, release: rel, downloads: 42, day: Hexpm.Utils.utc_yesterday())

  myrepo = insert(:repository, name: "myrepo")

  private = insert(:package,
    repository_id: myrepo.id,
    name: "private",
    package_owners: [build(:package_owner, owner: eric)],
    meta: build(:package_metadata,
      maintainers: [],
      licenses: [],
      links: %{"Github" => "http://example.com/github"},
      description: lorem
    )
  )

  insert(:release,
    package: private,
    version: "0.0.1",
    meta: build(:release_metadata,
      app: "private",
      build_tools: ["mix"]
    )
  )

  other_private = insert(:package,
    repository_id: myrepo.id,
    name: "other_private",
    package_owners: [build(:package_owner, owner: eric)],
    meta: build(:package_metadata,
      maintainers: [],
      licenses: [],
      links: %{"Github" => "http://example.com/github"},
      description: lorem
    )
  )

  insert(:release,
    package: other_private,
    version: "0.0.1",
    meta: build(:release_metadata,
      app: "other_private",
      build_tools: ["mix"]
    ),
    requirements: [
      build(:requirement,
        dependency: private,
        app: "private",
        requirement: ">= 0.0.0"
      )
    ]
  )

  insert(:repository_user, repository: myrepo, user: eric)

  Enum.each(1..100, fn index ->
    ups = insert(:package,
      name: "ups_#{index}",
      package_owners: [build(:package_owner, owner: joe)],
      meta: build(:package_metadata,
        maintainers: ["Joe Somebody"],
        licenses: [],
        links: %{"Github" => "http://example.com/github"},
        description: lorem))

    rel1 = insert(:release,
      package: ups,
      version: "0.0.1",
      meta: build(:release_metadata,
        app: "ups",
        build_tools: ["mix"]))

    rel2 = insert(:release,
      package: ups,
      version: "0.2.0",
      requirements: [
        build(:requirement,
          dependency: postgrex,
          app: "postgrex",
          requirement: "~> 0.1.0"),
        build(:requirement,
          dependency: decimal,
          app: "postgrex",
          requirement: "~> 0.1.0")],
      meta: build(:release_metadata,
        app: "ups",
        build_tools: ["mix"]))

    insert(:download, release: rel1, downloads: div(index, 2), day: Hexpm.Utils.utc_days_ago(35))
    insert(:download, release: rel2, downloads: div(index, 2), day: Hexpm.Utils.utc_yesterday())
  end)

  nerves = insert(:package,
    name: "nerves",
    package_owners: [build(:package_owner, owner: justin)],
    meta: build(:package_metadata,
      maintainers: ["Justin Schneck", "Frank Hunleth"],
      licenses: ["Apache 2.0"],
      links: %{"Github" => "http://example.com/github"},
      description: lorem,
      extra: %{
        "foo" => %{"bar" => "baz"},
        "key" => "value 1"}))

  rel = insert(:release,
    package: nerves,
    version: "0.0.1",
    meta: build(:release_metadata,
      app: "nerves",
      build_tools: ["mix"]))

  insert(:download, release: rel, downloads: 20, day: Hexpm.Utils.utc_yesterday())

  Enum.each(1..10, fn index ->
    nerves_pkg = insert(:package,
      name: "nerves_pkg_#{index}",
      package_owners: [build(:package_owner, owner: justin)],
      meta: build(:package_metadata,
        maintainers: ["Justin Schneck", "Frank Hunleth"],
        licenses: ["Apache 2.0"],
        links: %{"Github" => "http://example.com/github"},
        description: lorem,
        extra: %{
          "list" => ["a", "b", "c"],
          "foo" => %{"bar" => "baz"},
          "key" => "value"}))

    rel = insert(:release,
      package: nerves_pkg,
      version: "0.0.1",
      meta: build(:release_metadata,
        app: "nerves_pkg",
        build_tools: ["mix"]))

    insert(:download, release: rel, downloads: div(index, 2) + rem(index, 2), day: Hexpm.Utils.utc_yesterday())
  end)

  Hexpm.Repo.refresh_view(PackageDependant)
  Hexpm.Repo.refresh_view(PackageDownload)
  Hexpm.Repo.refresh_view(ReleaseDownload)
end)
