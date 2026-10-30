defmodule Hexpm.Repository.StagedReleaseCleanupWorker do
  use Oban.Worker, queue: :heavy, max_attempts: 10

  def enqueue([]), do: :ok

  def enqueue(keys) do
    %{keys: keys} |> new() |> Oban.insert!()
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"keys" => keys}}) do
    Enum.each(keys, &Hexpm.Store.delete(:repo_bucket, &1))
    :ok
  end
end
