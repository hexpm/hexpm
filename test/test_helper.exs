:logger.add_handler(:log_lines, Hexpm.LogLines, %{})
# The sandbox tests need Linux and util-linux 2.41 for setpriv's
# --seccomp-filter and enosys, so they run with --include sandbox where they can.
ExUnit.start(exclude: [:sandbox])

tmp_dir = Application.get_env(:hexpm, :tmp_dir)
File.rm_rf(tmp_dir)
File.mkdir_p(tmp_dir)

Hexpm.Store.Memory.start()
Hexpm.setup()
Hexpm.BlockAddress.reload()
Hexpm.Repository.RegistryBuilder.full(Hexpm.Repository.Repository.hexpm())
Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, :manual)
Hexpm.Fake.start()
