defmodule Hexpm.Diff.CacheDeleteWorker do
  @moduledoc """
  Deletes a package's cached diffs (`Hexpm.Diff.Cache.delete_package/2`)
  after one of its releases or the package itself is removed, off the request
  that removed it and retried when the store fails. One job per package while
  one is waiting.
  """

  use Oban.Worker,
    queue: :purge,
    max_attempts: 10,
    unique: [fields: [:worker, :args], states: [:available, :scheduled, :retryable]]

  def enqueue(repository, package) when is_binary(repository) and is_binary(package) do
    %{"repository" => repository, "package" => package}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository" => repository, "package" => package}}) do
    Hexpm.Diff.Cache.delete_package(repository, package)
  end
end
