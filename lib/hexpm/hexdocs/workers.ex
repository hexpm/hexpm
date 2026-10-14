defmodule Hexpm.Hexdocs.Workers.Upload do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  require Logger

  @stale_snooze 15
  @lock_snooze 30

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Hexdocs.upload(key)
  rescue
    Hexpm.Hexdocs.StaleArchiveError ->
      Logger.info(%{
        message: "Stale docs archive, snoozing",
        event: "hexdocs.stale",
        key: key,
        snooze: @stale_snooze
      })

      {:snooze, @stale_snooze}

    Hexpm.Hexdocs.LockedError ->
      Logger.info(%{
        message: "Hexdocs locked by another job, snoozing",
        event: "hexdocs.locked",
        key: key,
        snooze: @lock_snooze
      })

      {:snooze, @lock_snooze}
  end
end

defmodule Hexpm.Hexdocs.Workers.Search do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  require Logger

  @stale_snooze 15
  # Long enough for Typesense to free memory or for its capacity to be raised.
  @rejected_snooze 300

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Hexdocs.search(key)
  rescue
    Hexpm.Hexdocs.StaleArchiveError ->
      Logger.info(%{
        message: "Stale docs archive, snoozing",
        event: "hexdocs.stale",
        key: key,
        snooze: @stale_snooze
      })

      {:snooze, @stale_snooze}

    error in Hexpm.Hexdocs.Search.WriteRejectedError ->
      Logger.warning(%{
        message: "Search index rejected the write, snoozing",
        event: "hexdocs.search_rejected",
        key: key,
        error: Exception.message(error),
        snooze: @rejected_snooze
      })

      {:snooze, @rejected_snooze}
  end
end

defmodule Hexpm.Hexdocs.Workers.DeleteSearch do
  use Oban.Worker,
    queue: :heavy,
    # Below the publish jobs sharing the queue.
    priority: 9,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"package" => package, "version" => version}}) do
    Hexpm.Hexdocs.delete_search(package, version)
  end
end

defmodule Hexpm.Hexdocs.Workers.Delete do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  require Logger

  @stale_snooze 15
  @lock_snooze 30

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Hexdocs.delete(key)
  rescue
    Hexpm.Hexdocs.StaleArchiveError ->
      Logger.info(%{
        message: "Stale docs archive, snoozing",
        event: "hexdocs.stale",
        key: key,
        snooze: @stale_snooze
      })

      {:snooze, @stale_snooze}

    Hexpm.Hexdocs.LockedError ->
      Logger.info(%{
        message: "Hexdocs locked by another job, snoozing",
        event: "hexdocs.locked",
        key: key,
        snooze: @lock_snooze
      })

      {:snooze, @lock_snooze}
  end
end

defmodule Hexpm.Hexdocs.Workers.Sitemap do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  require Logger

  @lock_snooze 30

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Hexdocs.sitemap(key)
  rescue
    Hexpm.Hexdocs.LockedError ->
      Logger.info(%{
        message: "Hexdocs locked by another job, snoozing",
        event: "hexdocs.locked",
        key: key,
        snooze: @lock_snooze
      })

      {:snooze, @lock_snooze}
  end
end
