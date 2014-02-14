ExUnit.start

:application.set_env(:explex_web, :api_url, "http://explex.org/api")

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
