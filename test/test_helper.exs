ExUnit.start

:application.set_env(:explex_web, :api_url, "http://explex.org/api")
:application.set_env(:explex_web, :password_work_factor, 4)

Mix.Task.run "ecto.migrate", ["ExplexWeb.Repo"]

File.rm_rf!("tmp")
File.mkdir_p!("tmp")

defmodule ExplexWebTest.Case do
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.Postgres

  setup do
    Postgres.begin_test_transaction(ExplexWeb.Repo)
  end

  teardown do
    Postgres.rollback_test_transaction(ExplexWeb.Repo)
  end
end
