defmodule Hexpm.SecretScan do
  @moduledoc """
  Scans a published release for credentials and tells its owners.

  Runs from `Hexpm.SecretScan.Worker`, triggered by the same tarball upload that
  drives the preview, but as its own lower-priority job. Nothing else happens as
  a result: a finding does not block, revoke, retire, or appear anywhere public.
  The only output is an email to the people who can rotate the credential.
  """

  use Hexpm.Context

  require Logger

  alias Hexpm.Accounts.User
  alias Hexpm.Emails.Outbox
  alias Hexpm.Preview
  alias Hexpm.SecretScan.{Finding, Rules, Scan, Scanner}

  @category "secret_scan.findings"

  @doc """
  Downloads, unpacks and scans the tarball at a repo bucket `key`.

  This is the worker entry point. It fetches and unpacks the tarball itself
  rather than sharing the preview job's temp directory, so the two are
  independent; the extra download and unpack is the cost of that.
  """
  def scan_key(key) do
    with true <- Repo.write_mode?(),
         {:ok, repository, package, version} <- Preview.key_components(key),
         true <- Releases.exists?(repository, package, version) do
      {dir, file_paths, checksum, metadata} =
        Preview.download_and_unpack!(repository, package, version)

      scan(repository, package, version, dir, file_paths, checksum,
        ignore: ignore_globs(metadata)
      )
    else
      _ -> :ok
    end
  end

  # A package suppresses paths with `package: [secret_scan: [ignore: [...]]]` in
  # its mix.exs, which the client writes into the hex metadata. The metadata is
  # consult-encoded, so nested tables come back as proplists rather than maps.
  defp ignore_globs(%{"secret_scan" => config}) when is_list(config) do
    case List.keyfind(config, "ignore", 0) do
      {"ignore", globs} when is_list(globs) -> Enum.filter(globs, &is_binary/1)
      _ -> []
    end
  end

  defp ignore_globs(_metadata), do: []

  @doc """
  Scans an unpacked release and records what it finds.

  `dir` and `file_paths` are the temp directory and relative paths from the
  unpack. `tarball_checksum` is what makes a re-run free: a re-delivered upload
  event or a manual rerun arrives here with the same checksum and is skipped.
  """
  def scan(repository, package_name, version, dir, file_paths, tarball_checksum, opts \\ []) do
    # Oban runs against Hexpm.RepoBase, which does not go through the facade's
    # read-only guard, so preview jobs keep running during maintenance. There
    # is no point spending a CPU-bound scan on a transaction that will raise.
    if Repo.write_mode?() do
      scan_release(repository, package_name, version, dir, file_paths, tarball_checksum, opts)
    else
      :ok
    end
  end

  defp scan_release(repository, package_name, version, dir, file_paths, tarball_checksum, opts) do
    case Releases.get(repository, package_name, version) do
      nil ->
        # Removed while the job was running.
        :ok

      release ->
        release = Repo.preload(release, package: :repository)

        if scanned?(release, tarball_checksum) do
          :ok
        else
          run(release, dir, file_paths, tarball_checksum, opts)
        end
    end
  end

  @doc "Findings recorded for a release, in file order."
  def findings(release) do
    from(f in Finding,
      where: f.release_id == ^release.id,
      order_by: [asc: f.file_path, asc: f.line, asc: f.rule]
    )
    |> Repo.all()
  end

  @doc """
  Whether notification emails are turned on.

  Turning this on only affects releases published from then on. Anything
  scanned while it was off keeps its findings and is never re-examined, since
  `scanned?/2` keys on the tarball checksum, which has not changed. That is
  deliberate: mailing the whole ecosystem at once should be a decision someone
  makes, not a side effect of setting an environment variable.
  """
  def notify?, do: Application.get_env(:hexpm, :secret_scan_notify, false)

  defp scanned?(release, tarball_checksum) do
    from(s in Scan,
      where: s.release_id == ^release.id,
      where: s.tarball_checksum == ^tarball_checksum
    )
    |> Repo.exists?()
  end

  defp run(release, dir, file_paths, tarball_checksum, opts) do
    started = System.monotonic_time()
    {findings, truncated?} = Scanner.scan_files(dir, file_paths, opts)

    :telemetry.execute(
      [:hexpm, :secret_scan, :scan],
      %{duration: System.monotonic_time() - started, findings: length(findings)},
      %{truncated: truncated?, repository: release.package.repository_id}
    )

    {:ok, _result} =
      Multi.new()
      |> Multi.run(:lock, fn _repo, _changes -> lock_package(release) end)
      |> Multi.insert(:scan, scan_changeset(release, tarball_checksum, findings, truncated?),
        on_conflict: {:replace, [:tarball_checksum, :finding_count, :truncated, :updated_at]},
        conflict_target: :release_id
      )
      |> Multi.run(:findings, fn repo, _changes ->
        insert_findings(repo, release, findings, tarball_checksum)
      end)
      |> Multi.run(:notify, fn repo, changes -> notify(repo, release, changes) end)
      |> Repo.transaction()

    log(release, findings, truncated?)
    :ok
  end

  defp scan_changeset(release, tarball_checksum, findings, truncated?) do
    Scan.changeset(%Scan{}, %{
      release_id: release.id,
      tarball_checksum: tarball_checksum,
      finding_count: length(findings),
      truncated: truncated?
    })
  end

  # A rescan replaces what the previous one recorded. The tarball can change
  # under a version during the republish window, and leaving the old rows
  # behind would have `finding_count` disagree with the findings themselves and
  # show owners a file that is no longer in the package. Fingerprints already
  # reported still count as reported: the package-level dedup in `notify/3`
  # reads other releases, which this does not touch.
  defp insert_findings(repo, release, findings, tarball_checksum) do
    fingerprints = Enum.map(findings, & &1.fingerprint)

    repo.delete_all(
      from(f in Finding,
        where: f.release_id == ^release.id,
        where: f.fingerprint not in ^fingerprints
      )
    )

    do_insert_findings(repo, release, findings, tarball_checksum)
  end

  defp do_insert_findings(_repo, _release, [], _tarball_checksum), do: {:ok, []}

  defp do_insert_findings(repo, release, findings, tarball_checksum) do
    now = DateTime.utc_now()

    entries =
      Enum.map(findings, fn finding ->
        finding
        |> Map.take([:rule, :file_path, :line, :byte_offset, :fingerprint, :preview])
        |> Map.merge(%{
          release_id: release.id,
          package_id: release.package_id,
          tarball_checksum: tarball_checksum,
          inserted_at: now
        })
      end)

    {_count, inserted} =
      repo.insert_all(Finding, entries,
        on_conflict: :nothing,
        conflict_target: [:release_id, :fingerprint],
        returning: true
      )

    {:ok, inserted}
  end

  # Serialises scans of one package. Two versions publishing the same leaked
  # value race otherwise: under READ COMMITTED neither transaction sees the
  # other's findings, `reject_already_reported/3` finds nothing on both sides,
  # and the owners get the same credential mailed to them twice. The outbox's
  # own lock does not cover this, being keyed per release.
  defp lock_package(release) do
    Repo.advisory_xact_lock(:secret_scan, sub_key: release.package_id)
    {:ok, :locked}
  end

  # Notification dedupes on the package, not the release. Publishing the same
  # leaked value across ten versions is one problem and should be one email.
  defp notify(repo, release, %{findings: findings}) do
    fresh =
      findings
      |> Enum.filter(&Rules.notify?(&1.rule))
      |> reject_already_reported(repo, release)

    cond do
      fresh == [] -> {:ok, :nothing_to_report}
      not notify?() -> {:ok, :notification_disabled}
      true -> send_email(repo, release, fresh)
    end
  end

  defp reject_already_reported(findings, repo, release) do
    fingerprints = Enum.map(findings, & &1.fingerprint)

    reported =
      from(f in Finding,
        where: f.package_id == ^release.package_id,
        where: f.release_id != ^release.id,
        where: f.fingerprint in ^fingerprints,
        select: f.fingerprint
      )
      |> repo.all()
      |> MapSet.new()

    Enum.reject(findings, &MapSet.member?(reported, &1.fingerprint))
  end

  defp send_email(repo, release, findings) do
    # Rendering and validating the envelope raises on an email with nobody to
    # send it to, which a package whose owners were all removed and whose
    # publisher is an organization key really is. Do it before any SQL so that
    # case costs us the notification and not the whole scan.
    case prepare_email(repo, release, findings) do
      :no_recipients ->
        {:ok, :no_recipients}

      attrs ->
        Outbox.insert!(attrs)

        repo.update_all(
          from(s in Scan, where: s.release_id == ^release.id),
          set: [notified_at: DateTime.utc_now()]
        )

        {:ok, :sent}
    end
  end

  defp prepare_email(repo, release, findings) do
    email =
      repo
      |> recipients(release)
      |> Emails.secrets_detected(release.package.name, to_string(release.version), findings)

    if email.to == [] do
      Logger.warning(
        "Secret scan found #{length(findings)} notifiable findings in " <>
          "#{release.package.name} #{release.version} but it has no reachable owner"
      )

      :no_recipients
    else
      Outbox.prepare!(email,
        category: @category,
        group_key: "secret_scan:release:#{release.id}",
        scope_key: "secret_scan:package:#{release.package_id}"
      )
    end
  end

  # Three groups, and which one you land in does not depend on the kind of key
  # the release was published with:
  #
  #   * the package owners, who can rotate the credential
  #   * the admins of the organization that owns the package, because a leaked
  #     secret in an org's package is the org's problem whether or not the
  #     individual owner acts on it. For a package in an org's own repository
  #     that org comes from the repository; for a public package it is any
  #     organization sitting in the owners list, expanded by `Emails.email_to/2`.
  #   * the publisher, unless they have since left that organization
  #
  # An org and an org-user both expand to the same admin addresses, and the
  # final send dedupes by address, so overlap between the groups is harmless.
  defp recipients(repo, release) do
    preloads = [:emails, organization: [users: :emails]]

    owners =
      release.package
      |> assoc(:owners)
      |> repo.all()
      |> repo.preload(preloads)

    (owners ++ owning_organization(repo, release) ++ publisher(repo, release, preloads))
    |> Enum.uniq_by(&{&1.__struct__, &1.id})
  end

  # The organization behind a private repository. A public package (repository
  # 1) has no owning organization here; if an org owns it, the org is already
  # in the owners list above.
  defp owning_organization(_repo, %{package: %{repository_id: 1}}), do: []

  defp owning_organization(repo, release) do
    case repo.get(Organization, release.package.repository.organization_id) do
      nil -> []
      organization -> [repo.preload(organization, organization_users: [user: :emails])]
    end
  end

  # A publisher who has since lost access does not get told what is in a
  # private package. Rescans happen — a ruleset bump, a preview re-upload — and
  # each one would otherwise mail file paths from an organization's package to
  # someone removed from that organization, possibly for cause.
  defp publisher(_repo, %{publisher_id: nil}, _preloads), do: []

  defp publisher(repo, release, preloads) do
    publisher = from(u in User, where: u.id == ^release.publisher_id) |> repo.one()

    cond do
      is_nil(publisher) -> []
      release.package.repository_id == 1 -> [repo.preload(publisher, preloads)]
      still_a_member?(repo, release, publisher) -> [repo.preload(publisher, preloads)]
      true -> []
    end
  end

  defp still_a_member?(repo, release, publisher) do
    organization_id = release.package.repository.organization_id

    from(ou in Hexpm.Accounts.OrganizationUser,
      where: ou.organization_id == ^organization_id,
      where: ou.user_id == ^publisher.id
    )
    |> repo.exists?() or publisher.organization_id == organization_id
  end

  defp log(release, findings, truncated?) do
    if findings != [] do
      rules = findings |> Enum.map(& &1.rule) |> Enum.frequencies()

      Logger.info(
        "SECRET SCAN #{release.package.name} #{release.version} " <>
          "#{length(findings)} findings#{if truncated?, do: " (truncated)"} #{inspect(rules)}"
      )
    end
  end
end
