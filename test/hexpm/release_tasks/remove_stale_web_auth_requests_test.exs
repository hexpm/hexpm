defmodule Hexpm.ReleaseTasks.RemoveStaleWebAuthRequestsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{WebAuth, WebAuthRequest}
  alias Hexpm.Utils
  alias Hexpm.ReleaseTasks.RemoveStaleWebAuthRequests, as: RM

  setup do
    yesterday = Utils.datetime_utc_yesterday()

    for _ <- 1..5 do
      WebAuth.get_code("today's")
    end

    for _ <- 1..5 do
      WebAuth.get_code("yesterday's")
    end

    from(r in WebAuthRequest, where: r.key_name == "yesterday's")
    |> Repo.update_all(set: [inserted_at: yesterday])

    :ok
  end

  test "removes stale web auth requests" do
    RM.run()

    assert Repo.aggregate(WebAuthRequest, :count, :id) == 5
  end
end
