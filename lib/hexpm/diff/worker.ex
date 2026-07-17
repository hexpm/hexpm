defmodule Hexpm.Diff.Worker do
  use Oban.Worker,
    queue: :heavy,
    priority: 3,
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
    case Generator.generate(request) do
      {:error, :tarball_not_found} -> {:discard, :tarball_not_found}
      {:error, :checksum_mismatch} -> {:discard, :checksum_mismatch}
      {:error, {:invalid_tarball, _reason} = reason} -> {:discard, reason}
      result -> result
    end
  end
end
