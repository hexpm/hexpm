defmodule Hexpm.SecretScan.Worker do
  @moduledoc """
  Scans a published tarball for credentials, off the publish path.

  Runs as its own job rather than inside the preview upload: the scan is CPU
  work up to its budget, and pinning it to the preview job would put that work
  on the queue ahead of the file browser and diffs, and tie preview's
  reliability to the scanner's. At a lower priority than preview and diff, it
  waits behind the user-facing work. It is idempotent, so a transient failure
  retries rather than being dropped.
  """

  use Oban.Worker,
    queue: :heavy,
    priority: 5,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  @impl Oban.Worker
  def timeout(_job), do: 270_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: Hexpm.SecretScan.scan_key(key)
end
