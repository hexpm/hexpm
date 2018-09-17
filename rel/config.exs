use Mix.Releases.Config,
    default_release: :default,
    default_environment: :prod

environment :prod do
  set(include_erts: true)
  set(include_src: false)
end

release :hexpm do
  set(version: current_version(:hexpm))
  set(commands: [
    check_names: "rel/commands/check_names.sh",
    migrate: "rel/commands/migrate.sh",
    seed: "rel/commands/seed.sh",
    stats: "rel/commands/stats.sh"
  ])
end
