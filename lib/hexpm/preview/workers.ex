defmodule Hexpm.Preview.Workers.Upload do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  require Logger

  @stale_snooze 15

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Preview.upload(key)
  rescue
    Hexpm.Preview.StaleTarballError ->
      Logger.info(%{
        message: "Stale preview tarball, snoozing",
        event: "preview.stale",
        key: key,
        snooze: @stale_snooze
      })

      {:snooze, @stale_snooze}
  end
end

defmodule Hexpm.Preview.Workers.Delete do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  require Logger

  @stale_snooze 15

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Preview.delete(key)
  rescue
    Hexpm.Preview.StaleTarballError ->
      Logger.info(%{
        message: "Stale preview tarball, snoozing",
        event: "preview.stale",
        key: key,
        snooze: @stale_snooze
      })

      {:snooze, @stale_snooze}
  end
end

defmodule Hexpm.Preview.Workers.BackfillDocFiles do
  @moduledoc """
  Fills `release_doc_files` for releases published before it existed, one
  batch per job. Started once with `Hexpm.AdminTasks.backfill_doc_files/0`.
  """

  use Oban.Worker,
    queue: :heavy,
    # Below the Preview upload jobs sharing the queue.
    priority: 9,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"after_id" => after_id}}) do
    case Hexpm.Preview.backfill_doc_files(after_id, @batch_size) do
      {:ok, last_id} ->
        %{after_id: last_id} |> new() |> Oban.insert!()
        :ok

      :done ->
        :ok
    end
  end
end
