defmodule Hexpm.Diff.Worker do
  use Oban.Worker,
    queue: :heavy,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  alias Hexpm.Diff.{Generator, Request}

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, request} <- Request.from_args(args) do
      Generator.generate(request)
    end
  end
end
