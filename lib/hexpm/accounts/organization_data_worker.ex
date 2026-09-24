defmodule Hexpm.Accounts.OrganizationDataWorker do
  @moduledoc """
  Deletes the stored objects of a deleted organization, purges the CDN keys
  they were served under and records the deletion for the nightly backup.

  The job is inserted in the transaction that deletes the organization's
  rows, so a store request failing after the commit is retried rather than
  leaving objects that nothing points at any more. Every step can run again:
  deleting an emptied prefix deletes nothing and the backup acts on a marker
  written again the same way.

  `names` holds the organization's name and, when it was renamed, the name
  of its repository, which the objects were written under.
  """

  use Oban.Worker, queue: :purge, max_attempts: 10

  require Logger

  alias Hexpm.Repo

  # Fastly takes at most 256 surrogate keys in one purge request.
  @purge_keys_per_request 256

  def new_job(names, packages, policies) do
    new(%{
      "names" => Enum.uniq(names),
      "packages" => Enum.map(packages, fn {package, version} -> [package, version] end),
      "policies" => policies
    })
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Repo.write_mode!()

    names = Map.fetch!(args, "names")

    packages =
      Enum.map(Map.fetch!(args, "packages"), fn [package, version] -> {package, version} end)

    policies = Map.fetch!(args, "policies")

    counts =
      names
      |> Enum.flat_map(&prefixes/1)
      |> Enum.reduce(%{}, fn {bucket, prefix}, counts ->
        count = Hexpm.Store.delete_prefix(bucket, prefix)
        Map.update(counts, bucket, count, &(&1 + count))
      end)

    Enum.each(names, &Hexpm.Backups.delete_organization/1)

    purge_keys(
      :fastly_hexrepo,
      Enum.flat_map(names, &repository_cdn_keys(&1, packages, policies))
    )

    purge_keys(:fastly_hexdocs_private, Enum.flat_map(names, &docs_cdn_keys(&1, packages)))

    Logger.info(%{
      message: "Deleted the stored objects of an organization",
      event: "organization_data.delete",
      names: names,
      counts: counts
    })

    Hexpm.Slack.post(
      "Stored objects of organization #{Enum.join(names, " / ")} deleted: " <>
        Enum.map_join(counts, ", ", fn {bucket, count} -> "#{count} in #{bucket}" end)
    )

    :ok
  end

  @doc """
  Every object an organization named `name` has in a bucket, under one prefix
  per bucket: its registry, tarballs, docs archives and policies in the repo
  bucket, the uploads kept as sent under debug/, the unpacked preview files,
  the cached diffs and the unpacked private docs.
  """
  def prefixes(name) do
    unless Regex.match?(~r/\A[a-z0-9_]+\z/, name) do
      raise ArgumentError, "not an organization name: #{inspect(name)}"
    end

    [
      {:repo_bucket, "repos/#{name}/"},
      {:repo_bucket, "debug/tarballs/#{name}-"},
      {:repo_bucket, "debug/docs/#{name}-"},
      {:preview_bucket, "repos/#{name}/"},
      {:diff_bucket, "repos/#{name}/"},
      {:docs_private_bucket, "#{name}/"}
    ]
  end

  defp purge_keys(service, keys) do
    keys
    |> Enum.uniq()
    |> Enum.chunk_every(@purge_keys_per_request)
    |> Enum.each(&Hexpm.CDN.purge(service, &1))
  end

  # Every registry object of the repository carries `registry/<name>`, so the one
  # key covers names, versions and every packages/<package> object.
  defp repository_cdn_keys(name, packages, policies) do
    ["registry/#{name}"] ++
      Enum.map(policies, &"policy/#{name}/#{&1}") ++
      Enum.map(package_names(packages), &"preview/package/#{name}-#{&1}") ++
      Enum.flat_map(packages, fn
        {_package, nil} ->
          []

        {package, version} ->
          [
            "tarballs/#{name}-#{package}-#{version}",
            "docs/#{name}-#{package}-#{version}",
            "preview/package/#{name}-#{package}/version/#{version}"
          ]
      end)
  end

  defp docs_cdn_keys(name, packages) do
    Enum.flat_map(package_names(packages), fn package ->
      ["docspage/#{name}-#{package}", "docspage/#{name}-#{package}/docs_config.js"]
    end) ++
      Enum.flat_map(packages, fn
        {_package, nil} -> []
        {package, version} -> ["docspage/#{name}-#{package}/#{version}"]
      end)
  end

  defp package_names(packages) do
    packages |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
  end
end
