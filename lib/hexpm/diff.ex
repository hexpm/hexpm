defmodule Hexpm.Diff do
  import Ecto.Query

  alias Hexpm.Diff.{Cache, Request, Worker}

  @max_incomplete_jobs 20

  defmodule Piece do
    @moduledoc false

    @enforce_keys [:id, :key]
    defstruct @enforce_keys

    @opaque t :: %__MODULE__{id: String.t(), key: String.t()}
  end

  defdelegate prepare(package, from, to, opts), to: Request
  defdelegate fetch(request), to: Cache
  defdelegate fetch_piece(piece), to: Cache
  def piece_id(%Piece{id: id}), do: id

  def pending_job(%Request{} = request) do
    case get_incomplete_job(request) do
      nil -> :none
      job -> {:ok, job.id, job_status(job)}
    end
  end

  def enqueue(%Request{} = request) do
    if Hexpm.Repo.write_mode?() do
      case Hexpm.Repo.transaction(fn ->
             Hexpm.Repo.advisory_xact_lock(:diff)
             insert_job(request)
           end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :read_only}
    end
  end

  def job_status(%Oban.Job{state: state}), do: job_status_from_state(state)

  def job_status(job_id) when is_integer(job_id) do
    case Hexpm.Repo.get(Oban.Job, job_id) do
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

  defp insert_job(request) do
    case get_incomplete_job(request) do
      nil ->
        if incomplete_job_count() < @max_incomplete_jobs do
          request
          |> Request.to_args()
          |> Worker.new()
          |> Oban.insert()
        else
          Hexpm.Repo.rollback(:overloaded)
        end

      job ->
        {:ok, %{job | conflict?: true}}
    end
  end

  defp get_incomplete_job(request) do
    args = Request.to_args(request)

    incomplete_jobs_query()
    |> where([job], job.args == ^args)
    |> order_by([job], desc: job.id)
    |> limit(1)
    |> Hexpm.Repo.one()
  end

  defp incomplete_job_count do
    incomplete_jobs_query()
    |> Hexpm.Repo.aggregate(:count)
  end

  defp incomplete_jobs_query do
    states = Oban.Job.unique_states(:incomplete) |> Enum.map(&Atom.to_string/1)

    Oban.Job
    |> where([job], job.worker == ^Oban.Worker.to_string(Worker))
    |> where([job], job.state in ^states)
  end
end
