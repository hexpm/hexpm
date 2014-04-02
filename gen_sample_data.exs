alias HexWeb.User
alias HexWeb.Package
alias HexWeb.Release

lorem = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

HexWeb.Repo.transaction(fn ->
  { :ok, eric }  = User.create("eric", "eric@example.com", "eric")
  { :ok, jose } = User.create("jose", "jose@example.com", "jose")

  { :ok, decimal } =
    Package.create("decimal", eric,
      contributors: ["Eric Meadows-Jönsson"],
      licenses: ["Apache 2.0", "MIT"],
      links: [{ "Github", "http://example.com/github" },
              { "Documentation", "http://example.com/documentation" }],
      description: "Arbitrary precision decimal arithmetic for Elixir")

  { :ok, _ } = Release.create(decimal, "0.0.1", [])
  { :ok, _ } = Release.create(decimal, "0.0.2", [])
  { :ok, _ } = Release.create(decimal, "0.1.0", [])

  { :ok, postgrex } =
    Package.create("postgrex", eric,
      contributors: ["Eric Meadows-Jönsson", "José Valim"],
      licenses: ["Apache 2.0"],
      links: [{ "Github", "http://example.com/github" }],
      description: lorem)

  { :ok, _ } = Release.create(postgrex, "0.0.1", [])
  { :ok, _ } = Release.create(postgrex, "0.0.2", [decimal: "~> 0.0.1"])
  { :ok, _ } = Release.create(postgrex, "0.1.0", [decimal: "0.1.0"])

  { :ok, ecto } =
    Package.create("ecto", jose,
      contributors: ["Eric Meadows-Jönsson", "José Valim"],
      licenses: [],
      links: [{ "Github", "http://example.com/github" }],
      description: lorem)

  { :ok, _ } = Release.create(ecto, "0.0.1", [])
  { :ok, _ } = Release.create(ecto, "0.0.2", [postgrex: "~> 0.0.1"])
  { :ok, _ } = Release.create(ecto, "0.1.0", [postgrex: "~> 0.0.2"])
  { :ok, _ } = Release.create(ecto, "0.1.1", [postgrex: "~> 0.1.0"])
  { :ok, _ } = Release.create(ecto, "0.1.2", [postgrex: "== 0.1.0", decimal: "0.0.1"])
  { :ok, _ } = Release.create(ecto, "0.1.3", [postgrex: "0.1.0", decimal: "0.0.2"])
  { :ok, _ } = Release.create(ecto, "0.2.0", [postgrex: "~> 0.1.0", decimal: "~> 0.1.0"])
end)
