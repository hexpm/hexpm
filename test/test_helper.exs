ExUnit.start exclude: [:integration]

HexWeb.Config.url("http://hex.pm")
HexWeb.Config.store(HexWeb.Store.Local)
HexWeb.Config.password_work_factor(4)

Mix.Task.run "ecto.drop", ["HexWeb.Repo"]
Mix.Task.run "ecto.create", ["HexWeb.Repo"]
Mix.Task.run "ecto.migrate", ["HexWeb.Repo"]

File.rm_rf!("tmp")
File.mkdir_p!("tmp")

defmodule HexWebTest.Case do
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.Postgres

  setup do
    Path.wildcard("tmp/*") |> Enum.each(&File.rm_rf!(&1))

    Postgres.begin_test_transaction(HexWeb.Repo)
  end

  teardown do
    Postgres.rollback_test_transaction(HexWeb.Repo)
  end
end
