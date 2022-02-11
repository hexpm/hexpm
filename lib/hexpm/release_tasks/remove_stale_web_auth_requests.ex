defmodule Hexpm.ReleaseTasks.RemoveStaleWebAuthRequests do
  require Logger
  import Ecto.Query, only: [from: 2]
  alias Hexpm.Accounts.WebAuthRequest
  alias Hexpm.{Utils, Repo}

  def run() do
    # Trigger error_handler and rollbar reporting on 'hexpm eval ...'
    Task.async(&do_run/0)
    |> Task.await(:infinity)
  end

  def do_run() do
    find_stale_requests()
    |> log_result
    |> Repo.delete_all()
  end

  defp log_result(query) do
    stale_requests = Repo.aggregate(query, :count, :id)

    Logger.info("[remove_stale_web_auth_requests] job found #{stale_requests} stale_requests")

    query
  end

  def find_stale_requests() do
    from(r in WebAuthRequest, where: r.inserted_at <= ^Utils.datetime_utc_yesterday())
  end
end
