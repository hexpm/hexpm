import Hexpm.Factory
alias Hexpm.Accounts.Users
alias Hexpm.Repository.{PackageDependant, PackageDownload, ReleaseDownload}

Hexpm.Fake.start()

lorem =
  "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

password = &Bcrypt.hash_pwd_salt/1

Hexpm.Repo.transaction(fn ->
  insert(
    :key,
    user_id: Users.get("hexdocs").id,
    # user_secret: "2cd6d09334d4b00a2be4d532342b799b"
    secret_first: "e65e2dbb7e22694dc577e7b3d3328ff4",
    secret_second: "aebb59509b50226077c81216c2eba85b"
  )

  eric =
    insert(
      :user,
      username: "eric",
      emails: [build(:email, email: "eric@example.com")],
      password: password.("ericric"),
      role: "moderator",
      keys: [
        build(
          :key,
          # user_secret: "95f956c30a9e7b02409e5df12ad684bd"
          secret_first: "2c140dfe1429db3d449cf4265dc4cd1e",
          secret_second: "5bcf597057c2d04a1d228cd8c3254450"
        )
      ]
    )

  jose =
    insert(
      :user,
      username: "jose",
      emails: [build(:email, email: "jose@example.com")],
      password: password.("josejose")
    )

  joe =
    insert(
      :user,
      username: "joe",
      emails: [build(:email, email: "joe@example.com")],
      password: password.("joejoejoe")
    )

  justin =
    insert(
      :user,
      username: "justin",
      emails: [build(:email, email: "justin@example.com")],
      password: password.("justinjustin")
    )

  decimal =
    insert(
      :package,
      name: "decimal",
      package_owners: [build(:package_owner, user: eric)],
      meta:
        build(
          :package_metadata,
          licenses: ["Apache-2.0", "MIT"],
          links: %{
            "Github" => "http://example.com/github",
            "Documentation" => "http://example.com/documentation"
          },
          description: "Arbitrary precision decimal arithmetic for Elixir"
        )
    )

  insert(
    :release,
    package: decimal,
    version: "0.0.1",
    publisher: eric,
    meta:
      build(
        :release_metadata,
        app: "decimal",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: decimal,
    version: "0.0.2",
    publisher: eric,
    meta:
      build(
        :release_metadata,
        app: "decimal",
        build_tools: ["mix"]
      )
  )

  decimal_release =
    insert(
      :release,
      package: decimal,
      version: "0.1.0",
      publisher: eric,
      meta:
        build(
          :release_metadata,
          app: "decimal",
          build_tools: ["mix"]
        )
    )

  insert(
    :download,
    package: decimal,
    release: decimal_release,
    downloads: 1_200_000,
    day: Hexpm.Utils.utc_days_ago(180)
  )

  insert(
    :download,
    package: decimal,
    release: decimal_release,
    downloads: 200_000,
    day: Hexpm.Utils.utc_days_ago(90)
  )

  insert(
    :download,
    package: decimal,
    release: decimal_release,
    downloads: 56_000,
    day: Hexpm.Utils.utc_days_ago(35)
  )

  insert(:download,
    package: decimal,
    release: decimal_release,
    downloads: 1_000,
    day: Hexpm.Utils.utc_yesterday()
  )

  postgrex =
    insert(
      :package,
      name: "postgrex",
      package_owners: [build(:package_owner, user: eric), build(:package_owner, user: jose)],
      meta:
        build(
          :package_metadata,
          licenses: ["Apache-2.0"],
          links: %{"Github" => "http://example.com/github"},
          description: lorem
        )
    )

  insert(
    :release,
    package: postgrex,
    version: "0.0.1",
    publisher: jose,
    meta:
      build(
        :release_metadata,
        app: "postgrex",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: postgrex,
    version: "0.0.2",
    publisher: eric,
    requirements: [
      build(
        :requirement,
        dependency: decimal,
        app: "decimal",
        requirement: "~> 0.0.1"
      )
    ],
    meta:
      build(
        :release_metadata,
        app: "postgrex",
        build_tools: ["mix"]
      ),
    has_docs: true
  )

  postgrex_release =
    insert(
      :release,
      package: postgrex,
      version: "0.1.0",
      publisher: eric,
      requirements: [
        build(
          :requirement,
          dependency: decimal,
          app: "decimal",
          requirement: "0.1.0"
        )
      ],
      meta:
        build(
          :release_metadata,
          app: "postgrex",
          build_tools: ["mix"]
        )
    )

  insert(
    :download,
    package: postgrex,
    release: postgrex_release,
    downloads: 1_200_000,
    day: Hexpm.Utils.utc_days_ago(180)
  )

  insert(
    :download,
    package: postgrex,
    release: postgrex_release,
    downloads: 200_000,
    day: Hexpm.Utils.utc_days_ago(90)
  )

  insert(
    :download,
    package: postgrex,
    release: postgrex_release,
    downloads: 56_000,
    day: Hexpm.Utils.utc_days_ago(35)
  )

  insert(:download,
    package: postgrex,
    release: postgrex_release,
    downloads: 1_000,
    day: Hexpm.Utils.utc_yesterday()
  )

  ecto =
    insert(
      :package,
      name: "ecto",
      package_owners: [build(:package_owner, user: jose)],
      meta:
        build(
          :package_metadata,
          licenses: [],
          links: %{"Github" => "http://example.com/github"},
          description: lorem
        )
    )

  insert(
    :release,
    package: ecto,
    version: "0.0.1",
    publisher: jose,
    meta:
      build(
        :release_metadata,
        app: "ecto",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: ecto,
    version: "0.0.2",
    publisher: jose,
    requirements: [
      build(
        :requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "~> 0.0.1"
      )
    ],
    meta:
      build(
        :release_metadata,
        app: "ecto",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: ecto,
    version: "0.1.0",
    publisher: jose,
    requirements: [
      build(
        :requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "~> 0.0.2"
      )
    ],
    meta:
      build(
        :release_metadata,
        app: "ecto",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: ecto,
    version: "0.1.1",
    publisher: jose,
    requirements: [
      build(
        :requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "~> 0.1.0"
      )
    ],
    meta:
      build(
        :release_metadata,
        app: "ecto",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: ecto,
    version: "0.1.2",
    publisher: jose,
    requirements: [
      build(
        :requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "== 0.1.0"
      ),
      build(
        :requirement,
        dependency: decimal,
        app: "decimal",
        requirement: "0.1.0"
      )
    ],
    meta:
      build(
        :release_metadata,
        app: "ecto",
        build_tools: ["mix"]
      )
  )

  insert(
    :release,
    package: ecto,
    version: "0.1.3",
    publisher: jose,
    requirements: [
      build(
        :requirement,
        dependency: postgrex,
        app: "postgrex",
        requirement: "0.1.0"
      ),
      build(
        :requirement,
        dependency: decimal,
        app: "decimal",
        requirement: "0.1.0"
      )
    ],
    meta:
      build(
        :release_metadata,
        app: "ecto",
        build_tools: ["mix"]
      )
  )

  rel =
    insert(
      :release,
      package: ecto,
      version: "0.2.0",
      publisher: jose,
      requirements: [
        build(
          :requirement,
          dependency: postgrex,
          app: "postgrex",
          requirement: "~> 0.1.0"
        ),
        build(
          :requirement,
          dependency: decimal,
          app: "decimal",
          requirement: "~> 0.1.0"
        )
      ],
      meta:
        build(
          :release_metadata,
          app: "ecto",
          build_tools: ["mix"]
        ),
      has_docs: true
    )

  insert(:download,
    package: ecto,
    release: rel,
    downloads: 1_500_000,
    day: Hexpm.Utils.utc_days_ago(180)
  )

  insert(:download,
    package: ecto,
    release: rel,
    downloads: 200_000,
    day: Hexpm.Utils.utc_days_ago(90)
  )

  insert(:download, package: ecto, release: rel, downloads: 1, day: Hexpm.Utils.utc_days_ago(45))

  insert(:download,
    package: ecto,
    release: rel,
    downloads: 56_000,
    day: Hexpm.Utils.utc_days_ago(35)
  )

  insert(:download, package: ecto, release: rel, downloads: 1, day: Hexpm.Utils.utc_days_ago(2))
  insert(:download, package: ecto, release: rel, downloads: 42, day: Hexpm.Utils.utc_yesterday())

  myrepo =
    insert(
      :repository,
      name: "myrepo",
      organization: build(:organization, name: "myrepo", user: build(:user, username: "myrepo"))
    )

  private =
    insert(
      :package,
      repository_id: myrepo.id,
      name: "private",
      package_owners: [build(:package_owner, user: eric)],
      meta:
        build(
          :package_metadata,
          licenses: [],
          links: %{"Github" => "http://example.com/github"},
          description: lorem
        )
    )

  insert(
    :release,
    package: private,
    version: "0.0.1",
    publisher: eric,
    meta:
      build(
        :release_metadata,
        app: "private",
        build_tools: ["mix"]
      )
  )

  other_private =
    insert(
      :package,
      repository_id: myrepo.id,
      name: "other_private",
      package_owners: [build(:package_owner, user: eric)],
      meta:
        build(
          :package_metadata,
          licenses: [],
          links: %{"Github" => "http://example.com/github"},
          description: lorem
        )
    )

  insert(
    :release,
    package: other_private,
    version: "0.0.1",
    publisher: eric,
    meta:
      build(
        :release_metadata,
        app: "other_private",
        build_tools: ["mix"]
      ),
    requirements: [
      build(
        :requirement,
        dependency: private,
        app: "private",
        requirement: ">= 0.0.0"
      )
    ]
  )

  insert(:organization_user, organization: myrepo.organization, user: eric, role: "admin")

  Enum.each(1..100, fn index ->
    ups =
      insert(
        :package,
        name: "ups_#{index}",
        package_owners: [build(:package_owner, user: joe)],
        meta:
          build(
            :package_metadata,
            licenses: [],
            links: %{"Github" => "http://example.com/github"},
            description: lorem
          )
      )

    rel1 =
      insert(
        :release,
        package: ups,
        version: "0.0.1",
        publisher: joe,
        meta:
          build(
            :release_metadata,
            app: "ups",
            build_tools: ["mix"]
          )
      )

    rel2 =
      insert(
        :release,
        package: ups,
        version: "0.2.0",
        publisher: joe,
        requirements: [
          build(
            :requirement,
            dependency: postgrex,
            app: "postgrex",
            requirement: "~> 0.1.0"
          ),
          build(
            :requirement,
            dependency: decimal,
            app: "postgrex",
            requirement: "~> 0.1.0"
          )
        ],
        meta:
          build(
            :release_metadata,
            app: "ups",
            build_tools: ["mix"]
          )
      )

    insert(:download,
      package: ups,
      release: rel1,
      downloads: div(index, 2),
      day: Hexpm.Utils.utc_days_ago(180)
    )

    insert(:download,
      package: ups,
      release: rel1,
      downloads: div(index, 2),
      day: Hexpm.Utils.utc_days_ago(90)
    )

    insert(:download,
      package: ups,
      release: rel1,
      downloads: div(index, 2),
      day: Hexpm.Utils.utc_days_ago(35)
    )

    insert(:download,
      package: ups,
      release: rel2,
      downloads: div(index, 2),
      day: Hexpm.Utils.utc_yesterday()
    )
  end)

  nerves =
    insert(
      :package,
      name: "nerves",
      package_owners: [build(:package_owner, user: justin)],
      meta:
        build(
          :package_metadata,
          licenses: ["Apache-2.0"],
          links: %{"Github" => "http://example.com/github"},
          description: lorem,
          extra: %{"foo" => %{"bar" => "baz"}, "key" => "value 1"}
        )
    )

  rel =
    insert(
      :release,
      package: nerves,
      version: "0.0.1",
      publisher: justin,
      meta:
        build(
          :release_metadata,
          app: "nerves",
          build_tools: ["mix"]
        )
    )

  insert(:download, package: nerves, release: rel, downloads: 20, day: Hexpm.Utils.utc_yesterday())

  Enum.each(1..10, fn index ->
    nerves =
      insert(
        :package,
        name: "nerves_pkg_#{index}",
        package_owners: [build(:package_owner, user: justin)],
        meta:
          build(
            :package_metadata,
            licenses: ["Apache-2.0"],
            links: %{"Github" => "http://example.com/github"},
            description: lorem,
            extra: %{"list" => ["a", "b", "c"], "foo" => %{"bar" => "baz"}, "key" => "value"}
          )
      )

    rel =
      insert(
        :release,
        package: nerves,
        version: "0.0.1",
        publisher: justin,
        meta:
          build(
            :release_metadata,
            app: "nerves_pkg",
            build_tools: ["mix"]
          )
      )

    insert(
      :download,
      package: nerves,
      release: rel,
      downloads: div(index, 2) + rem(index, 2),
      day: Hexpm.Utils.utc_yesterday()
    )
  end)

  Hexpm.Repo.refresh_view(PackageDependant)
  Hexpm.Repo.refresh_view(PackageDownload)
  Hexpm.Repo.refresh_view(ReleaseDownload)
end)

Hexpm.Repository.RegistryBuilder.full(Hexpm.Repository.Repositories.get("hexpm"))
