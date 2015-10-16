defmodule Mix.Tasks.Hexweb.Stats do
  use Mix.Task
  require Logger

  @shortdoc "Calculates yesterdays download stats"

  def run(_args) do
    Mix.Task.run "app.start"

    buckets = Application.get_env(:hex_web, :logs_buckets)

    try do
      {time, {memory, size}} = :timer.tc(fn ->
        HexWeb.Stats.Job.run(HexWeb.Util.yesterday(), buckets)
      end)
      Logger.info "STATS_JOB_COMPLETED #{size} downloads (#{div time, 1000}ms, #{div memory, 1024}kb)"
    catch
      kind, error ->
        stacktrace = System.stacktrace
        Logger.error "STATS_JOB_FAILED"
        HexWeb.Util.log_error(kind, error, stacktrace)

        System.at_exit(fn
          0 ->
            System.halt(1)
          _ ->
            :ok
      end)
    end
  end
end
