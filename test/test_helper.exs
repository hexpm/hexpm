ExUnit.start()

tmp_dir = Application.get_env(:hexpm, :tmp_dir)
File.rm_rf(tmp_dir)
File.mkdir_p(tmp_dir)

Hexpm.setup()
Hexpm.BlockAddress.reload()
Hexpm.Repository.RegistryBuilder.full(Hexpm.Repository.Repository.hexpm())
Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, :manual)
Hexpm.Fake.start()
