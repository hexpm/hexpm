import Hexpm.Factory
alias Hexpm.Accounts.Users
alias Hexpm.OAuth.Client
alias Hexpm.Repository.{PackageDownload, ReleaseDownload}

Hexpm.Fake.start()
Hexpm.setup()

lorem =
  "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

password = &Bcrypt.hash_pwd_salt/1

Hexpm.Repo.transaction(fn ->
  insert(:oauth_client,
    name: "Hex CLI",
    client_id: "78ea6566-89fd-481e-a1d6-7d9d78eacca8",
    client_type: "public",
    allowed_grant_types: Client.valid_grant_types(),
    allowed_scopes: ["api", "api:read", "api:write", "repositories"]
  )

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

  maennchen =
    insert(
      :user,
      username: "maennchen",
      emails: [build(:email, email: "jonatan@example.com")],
      password: password.("maennchenmaennchen")
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

  insert(
    :user,
    username: "nopkg",
    emails: [build(:email, email: "nopkg@example.com")],
    password: password.("nopkgnopkg")
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

  insert_with_tarball(
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

  insert_with_tarball(
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
    insert_with_tarball(
      :release,
      package: decimal,
      version: "0.1.0",
      publisher: eric,
      meta:
        build(
          :release_metadata,
          app: "decimal",
          build_tools: ["mix"]
        ),
      has_docs: true
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

  oidcc =
    insert(
      :package,
      name: "oidcc",
      package_owners: [build(:package_owner, user: maennchen)],
      meta:
        build(
          :package_metadata,
          licenses: ["Apache-2.0"],
          links: %{
            "Github" => "https://github.com/erlef/oidcc",
            "Documentation" => "https://hexdocs.pm/oidcc/"
          },
          description: "OpenID Connect client library for the BEAM."
        )
    )

  insert_with_tarball(
    :release,
    package: oidcc,
    version: "3.0.0",
    publisher: maennchen,
    meta:
      build(
        :release_metadata,
        app: "oidcc",
        build_tools: ["mix"]
      )
  )

  insert_with_tarball(
    :release,
    package: oidcc,
    version: "3.0.2",
    publisher: maennchen,
    meta:
      build(
        :release_metadata,
        app: "oidcc",
        build_tools: ["mix"]
      )
  )

  insert_with_tarball(
    :release,
    package: oidcc,
    version: "3.1.0",
    publisher: maennchen,
    meta: build(:release_metadata, app: "oidcc", build_tools: ["mix"])
  )

  insert_with_tarball(
    :release,
    package: oidcc,
    version: "3.1.1",
    publisher: maennchen,
    meta: build(:release_metadata, app: "oidcc", build_tools: ["mix"]),
    retirement: %Hexpm.Repository.ReleaseRetirement{
      reason: "deprecated",
      message: "Use 3.1.2 instead"
    }
  )

  insert_with_tarball(
    :release,
    package: oidcc,
    version: "3.1.2",
    publisher: maennchen,
    meta: build(:release_metadata, app: "oidcc", build_tools: ["mix"])
  )

  insert_with_tarball(
    :release,
    package: oidcc,
    version: "3.1.3",
    publisher: maennchen,
    meta: build(:release_metadata, app: "oidcc", build_tools: ["mix"]),
    retirement: %Hexpm.Repository.ReleaseRetirement{
      reason: "security",
      message: "Known security vulnerability"
    }
  )

  oidcc_advisory_record = %{
    id: "GHSA-mj35-2rgf-cv8p",
    summary:
      "OpenID Connect client Atom Exhaustion in provider configuration worker ets table location",
    aliases: ["CVE-2024-31209"],
    published_at: ~U[2024-04-03 16:46:30Z],
    modified_at: ~U[2024-04-05 01:28:39Z],
    withdrawn_at: nil,
    cvss_vector: "CVSS:3.1/AV:L/AC:H/PR:H/UI:N/S:C/C:N/I:N/A:H",
    cvss_score: 5.5,
    cvss_rating: "medium",
    references: [
      %{
        type: "WEB",
        url: "https://github.com/erlef/oidcc/security/advisories/GHSA-mj35-2rgf-cv8p"
      }
    ],
    affected: [
      %{
        package: "oidcc",
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")],
        versions: ["3.0.0"]
      },
      %{
        package: "oidcc",
        requirements: [Version.parse_requirement!(">= 3.1.2 and < 3.1.4")],
        versions: ["3.1.2", "3.1.3"]
      }
    ]
  }

  oidcc_ghsa_alias_advisory_record = %{
    id: "GHSA-628h-q48j-jr6q",
    summary: "GHSA source for a duplicate alias advisory",
    aliases: ["CVE-2026-32689"],
    published_at: ~U[2026-05-08 00:00:00Z],
    modified_at: ~U[2026-05-08 00:00:00Z],
    withdrawn_at: nil,
    cvss_vector: nil,
    cvss_score: nil,
    cvss_rating: nil,
    references: [
      %{
        type: "WEB",
        url: "https://github.com/phoenixframework/phoenix/security/advisories/GHSA-628h-q48j-jr6q"
      }
    ],
    affected: [
      %{
        package: "oidcc",
        requirements: [Version.parse_requirement!(">= 3.0.0 and < 3.0.2")],
        versions: ["3.0.0"]
      }
    ]
  }

  oidcc_eef_alias_advisory_record = %{
    id: "EEF-CVE-2026-32689",
    summary: "EEF source for a duplicate alias advisory",
    aliases: ["CVE-2026-32689", "GHSA-628h-q48j-jr6q"],
    published_at: ~U[2026-05-05 00:00:00Z],
    modified_at: ~U[2026-05-10 00:00:00Z],
    withdrawn_at: nil,
    cvss_vector: nil,
    cvss_score: nil,
    cvss_rating: nil,
    references: [
      %{type: "ADVISORY", url: "https://cna.erlef.org/cves/CVE-2026-32689.html"}
    ],
    affected: [
      %{
        package: "oidcc",
        requirements: [Version.parse_requirement!(">= 3.1.2 and < 3.1.4")],
        versions: ["3.1.2", "3.1.3"]
      }
    ]
  }

  Hexpm.Security.Advisories.upsert(
    [
      oidcc_advisory_record,
      oidcc_ghsa_alias_advisory_record,
      oidcc_eef_alias_advisory_record
    ],
    %{"oidcc" => oidcc.id}
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

  insert_with_tarball(
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

  insert_with_tarball(
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
    insert_with_tarball(
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

  insert_with_tarball(
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

  insert_with_tarball(
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

  insert_with_tarball(
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

  insert_with_tarball(
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

  insert_with_tarball(
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

  insert_with_tarball(
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
    insert_with_tarball(
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

  insert_with_tarball(
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

  insert_with_tarball(
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
      insert_with_tarball(
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
      insert_with_tarball(
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
    insert_with_tarball(
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

  today = Date.utc_today()

  Enum.each(1..31, fn day ->
    insert(:download,
      package: nerves,
      release: rel,
      downloads: Enum.random(1..100),
      day: Date.add(today, -day)
    )
  end)

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
      insert_with_tarball(
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

  Hexpm.Repo.refresh_view(PackageDownload, concurrently: false)
  Hexpm.Repo.refresh_view(ReleaseDownload, concurrently: false)
end)

Hexpm.Repository.RegistryBuilder.full(Hexpm.Repository.Repositories.get("hexpm"))
Hexpm.Repository.RegistryBuilder.full(Hexpm.Repository.Repositories.get("myrepo"))
