defmodule Hexpm.Accounts.PrivateAccessLogsSweep do
  @moduledoc """
  Deletes the private access log lines of names that no longer belong to an
  organization.

  The access log retention job in hexpm-ops keeps a year-old private line under
  `org=<name>/` in the private access log bucket, where `<name>` is the
  repository named in the request. `Hexpm.Accounts.OrganizationDataWorker`
  deletes that prefix when it deletes an organization, but lines also land
  there for organizations deleted before it existed and for requests naming a
  repository that never existed. Their purpose, establishing whether anyone
  accessed an organization's private packages, ends with the organization, so
  any prefix whose name is neither an organization's nor a repository's is
  deleted.
  """

  use Oban.Worker,
    queue: :periodic,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hexpm.Accounts.Organization
  alias Hexpm.Repo
  alias Hexpm.Repository.Repository

  @bucket :access_logs_private_bucket

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Repo.write_mode?() do
      run()
    end

    :ok
  end

  def run() do
    names = existing_names()

    deleted =
      @bucket
      |> Hexpm.Store.list_prefixes("")
      |> Enum.flat_map(&orphan(&1, names))
      |> Enum.map(fn {name, prefix} -> {name, Hexpm.Store.delete_prefix(@bucket, prefix)} end)

    for {name, count} <- deleted do
      Logger.info(%{
        message: "Deleted the private access log lines of a name without an organization",
        event: "private_access_logs.sweep",
        name: name,
        count: count
      })
    end

    length(deleted)
  end

  # `org=-/` holds the object that keeps the bucket's BigQuery table queryable
  # and is not a name.
  defp orphan("org=" <> rest = prefix, names) do
    name = String.trim_trailing(rest, "/")

    if Regex.match?(~r/\A[a-z0-9_]+\z/, name) and name != "hexpm" and
         not MapSet.member?(names, name) do
      [{name, prefix}]
    else
      []
    end
  end

  defp orphan(_prefix, _names), do: []

  defp existing_names() do
    organizations = Repo.all(from(o in Organization, select: o.name))
    repositories = Repo.all(from(r in Repository, select: r.name))
    MapSet.new(organizations ++ repositories)
  end
end
