use Mix.Releases.Config,
    default_release: :default,
    default_environment: :prod

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(pre_configure_hook: "rel/hooks/pre_configure")
end

release :hexpm do
  set(version: current_version(:hexpm))
  set(commands: [
    check_names: "rel/commands/check_names.sh",
    migrate: "rel/commands/migrate.sh",
    script: "rel/commands/script.sh",
    seed: "rel/commands/seed.sh",
    stats: "rel/commands/stats.sh"
  ])
  set(cookie: "")
  set(vm_args: "rel/vm.args")
end
