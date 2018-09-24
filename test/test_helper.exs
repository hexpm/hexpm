ExUnit.start()

tmp_dir = Application.get_env(:hexpm, :tmp_dir)
File.rm_rf(tmp_dir)
File.mkdir_p(tmp_dir)

Hexpm.BlockAddress.reload()
Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, :manual)
Hexpm.Fake.start()
