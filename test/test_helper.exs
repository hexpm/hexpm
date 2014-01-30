ExUnit.start

Mix.Task.run "ecto.migrate", ["ExplexWeb.Repo"]
:application.set_env(:explex_web, :password_work_factor, 4)

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
