defmodule Hexpm.Preview.Workers.Upload do
  use Oban.Worker,
    queue: :heavy,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: Hexpm.Preview.upload(key)
end

defmodule Hexpm.Preview.Workers.Delete do
  use Oban.Worker,
    queue: :heavy,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: Hexpm.Preview.delete(key)
end

defmodule Hexpm.Preview.Workers.Sitemap do
  use Oban.Worker,
    queue: :heavy,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: Hexpm.Preview.sitemap(key)
end
