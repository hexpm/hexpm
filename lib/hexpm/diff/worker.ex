defmodule Hexpm.Diff.Worker do
  use Oban.Worker,
    queue: :heavy,
    priority: 1,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  alias Hexpm.Diff.{Generator, Request}

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Request.from_args(args) do
      {:ok, request} -> generate(request)
      {:error, reason} -> {:discard, reason}
    end
  end

  defp generate(request) do
    task = Task.async(fn -> Generator.generate(request) end)
    timeout = Application.fetch_env!(:hexpm, :diff_timeout)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result(result)
      nil -> {:discard, :timeout}
    end
  end

  defp result({:error, :tarball_not_found}), do: {:discard, :tarball_not_found}
  defp result({:error, :checksum_mismatch}), do: {:discard, :checksum_mismatch}
  defp result({:error, {:invalid_tarball, _reason} = reason}), do: {:discard, reason}
  defp result(result), do: result
end
