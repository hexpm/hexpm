defmodule Hexpm.Hexdocs.Workers.Upload do
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
    Hexpm.Hexdocs.upload(key)
  rescue
    Hexpm.Hexdocs.StaleArchiveError ->
      Logger.info("STALE DOCS ARCHIVE #{key} snooze=#{@stale_snooze}s")
      {:snooze, @stale_snooze}
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

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Hexpm.Hexdocs.search(key)
  rescue
    Hexpm.Hexdocs.StaleArchiveError ->
      Logger.info("STALE DOCS ARCHIVE #{key} snooze=#{@stale_snooze}s")
      {:snooze, @stale_snooze}
  end
end

defmodule Hexpm.Hexdocs.Workers.Delete do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: Hexpm.Hexdocs.delete(key)
end

defmodule Hexpm.Hexdocs.Workers.Sitemap do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: Hexpm.Hexdocs.sitemap(key)
end
