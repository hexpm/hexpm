defmodule Hexpm.Diff do
  use Hexpm.Context

  import Ecto.Query

  alias Hexpm.Diff.{Cache, Request, Worker}

  @max_incomplete_jobs 20

  defmodule Piece do
    @moduledoc false

    @enforce_keys [:id, :key]
    defstruct @enforce_keys ++ [file: nil]

    @opaque t :: %__MODULE__{id: String.t(), key: String.t(), file: String.t() | nil}
  end

  defdelegate prepare(package, from, to, opts), to: Request
  defdelegate fetch(request), to: Cache
  defdelegate fetch_piece(piece), to: Cache
  def piece_id(%Piece{id: id}), do: id
  def piece_file(%Piece{file: file}), do: file

  def pending_job(%Request{} = request) do
    case get_latest_job(request) do
      nil -> :none
      job -> {:ok, job.id, job_status(job)}
    end
  end

  def enqueue(%Request{} = request) do
    if Hexpm.Repo.write_mode?() do
      case Repo.transaction(fn ->
             Repo.advisory_xact_lock(:diff)
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
    case Repo.get(Oban.Job, job_id) do
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
          Repo.rollback(:overloaded)
        end

      job ->
        {:ok, %{job | conflict?: true}}
    end
  end

  defp get_incomplete_job(request) do
    request
    |> jobs_query()
    |> where([job], job.state in ^incomplete_states())
    |> order_by([job], desc: job.id)
    |> limit(1)
    |> Repo.one()
  end

  defp get_latest_job(request) do
    request
    |> jobs_query()
    |> order_by([job], desc: job.id)
    |> limit(1)
    |> Repo.one()
  end

  defp jobs_query(request) do
    args = Request.to_args(request)

    Oban.Job
    |> where([job], job.worker == ^Oban.Worker.to_string(Worker))
    |> where([job], job.args == ^args)
  end

  defp incomplete_job_count do
    incomplete_jobs_query()
    |> Repo.aggregate(:count)
  end

  defp incomplete_jobs_query do
    Oban.Job
    |> where([job], job.worker == ^Oban.Worker.to_string(Worker))
    |> where([job], job.state in ^incomplete_states())
  end

  defp incomplete_states, do: Oban.Job.unique_states(:incomplete) |> Enum.map(&Atom.to_string/1)
end
