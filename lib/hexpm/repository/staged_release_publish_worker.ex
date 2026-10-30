defmodule Hexpm.Repository.StagedReleasePublishWorker do
  use Oban.Worker,
    queue: :heavy,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete, keys: [:id]]

  def enqueue(id), do: %{id: id} |> new() |> Oban.insert!()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) do
    if Hexpm.Repo.in_transaction?() do
      {:snooze, 1}
    else
      case Hexpm.Repository.StagedReleases.complete_approval(id) do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end
end
