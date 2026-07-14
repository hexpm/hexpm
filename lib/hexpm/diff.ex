defmodule Hexpm.Diff do
  alias Hexpm.Diff.{Request, Storage, Worker}

  defmodule Piece do
    @moduledoc false

    @enforce_keys [:id, :key]
    defstruct @enforce_keys

    @opaque t :: %__MODULE__{id: String.t(), key: String.t()}
  end

  defdelegate prepare(package, from, to, opts), to: Request
  defdelegate fetch(request), to: Storage
  defdelegate fetch_piece(piece), to: Storage

  def enqueue(%Request{} = request) do
    request
    |> Request.to_args()
    |> Worker.new()
    |> Oban.insert()
  end

  def job_status(%Oban.Job{state: state}), do: job_status_from_state(state)

  def job_status(job_id) when is_integer(job_id) do
    case Hexpm.RepoBase.get(Oban.Job, job_id) do
      nil -> :missing
      job -> job_status(job)
    end
  end

  defp job_status_from_state("executing"), do: :running
  defp job_status_from_state("retryable"), do: :retrying
  defp job_status_from_state("completed"), do: :completed
  defp job_status_from_state("discarded"), do: :discarded
  defp job_status_from_state("cancelled"), do: :cancelled
  defp job_status_from_state(_state), do: :queued
end
