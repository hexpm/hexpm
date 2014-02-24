ExUnit.start

:application.set_env(:hex_web, :url, "http://hex.pm")
:application.set_env(:hex_web, :password_work_factor, 4)

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
