defmodule Hexpm.Oban.PrunerTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Oban.Pruner

  @day 24 * 60 * 60

  defp job(state, age_in_days) do
    at = DateTime.add(DateTime.utc_now(), -age_in_days * @day)

    finished =
      case state do
        "completed" -> [completed_at: at]
        "cancelled" -> [cancelled_at: at]
        "discarded" -> [discarded_at: at]
        _ -> []
      end

    Hexpm.Repo.insert!(
      struct!(
        Oban.Job,
        [
          worker: "Fake",
          queue: "periodic",
          args: %{},
          state: state,
          inserted_at: at,
          scheduled_at: at
        ] ++ finished
      )
    )
  end

  defp prune(opts) do
    opts
    |> Keyword.put(:conf, Oban.config(Oban))
    |> then(&struct!(Pruner, &1))
    |> Pruner.prune_jobs()
  end

  defp states() do
    from(j in Oban.Job, select: {j.state, count(j.id)}, group_by: j.state)
    |> Hexpm.Repo.all()
    |> Map.new()
  end

  describe "prune_jobs/1" do
    test "keeps failures for longer than successes" do
      job("completed", 5)
      job("cancelled", 5)
      job("discarded", 5)
      job("completed", 1)
      job("discarded", 400)

      assert %{pruned_succeeded: 2, pruned_failed: 1} =
               prune(max_age: 3 * @day, discarded_max_age: 365 * @day)

      # The five day old success and cancellation go, the five day old failure
      # stays, and only the failure older than a year goes with them.
      assert states() == %{"completed" => 1, "discarded" => 1}
    end

    test "leaves jobs that have not finished alone" do
      for state <- ~w(available scheduled executing retryable), do: job(state, 400)

      prune(max_age: 1, discarded_max_age: 1)

      assert states() == %{
               "available" => 1,
               "scheduled" => 1,
               "executing" => 1,
               "retryable" => 1
             }
    end

    test "deletes no more than the limit in one pass" do
      for _ <- 1..5, do: job("completed", 5)

      assert %{pruned_count: 2} =
               prune(max_age: 3 * @day, discarded_max_age: 365 * @day, limit: 2)

      assert states() == %{"completed" => 3}
    end
  end
end
