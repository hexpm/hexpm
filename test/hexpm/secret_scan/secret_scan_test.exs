defmodule Hexpm.SecretScanTest do
  use Hexpm.DataCase, async: false

  import Swoosh.TestAssertions

  alias Hexpm.SecretScan
  alias Hexpm.SecretScan.{Finding, Scan}

  @github_token "ghp_" <> "016Cq2mKvXbNzR8dLpWyTuAeH3jFgS4iOU7Q"
  @other_token "ghp_" <> "9zXwVuTsRqPoNmLkJiHgFeDcBa87654321Zy"
  @checksum <<1, 2, 3, 4>>

  setup do
    dir = Path.join(System.tmp_dir!(), "secret-scan-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    notify = Application.get_env(:hexpm, :secret_scan_notify)
    Application.put_env(:hexpm, :secret_scan_notify, true)
    on_exit(fn -> Application.put_env(:hexpm, :secret_scan_notify, notify) end)

    user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])

    {:ok, dir: dir, user: user, package: package}
  end

  defp write(dir, path, contents) do
    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
    path
  end

  defp scan(package, version, dir, paths, checksum \\ @checksum) do
    SecretScan.scan("hexpm", package.name, version, dir, paths, checksum)
  end

  test "records findings and the scan itself", %{dir: dir, package: package} do
    release = insert(:release, package: package, version: "1.0.0")
    path = write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")

    assert scan(package, "1.0.0", dir, [path]) == :ok

    assert [finding] = SecretScan.findings(release)
    assert finding.rule == "github-pat"
    assert finding.file_path == ".env"
    assert finding.package_id == package.id
    assert finding.tarball_checksum == @checksum
    refute finding.preview =~ @github_token

    assert scan_row = Repo.get_by(Scan, release_id: release.id)
    assert scan_row.finding_count == 1
    assert scan_row.tarball_checksum == @checksum
    refute is_nil(scan_row.notified_at)
  end

  test "records a clean release so it is not rescanned", %{dir: dir, package: package} do
    release = insert(:release, package: package, version: "1.0.0")
    path = write(dir, "lib/app.ex", "defmodule App do\nend\n")

    assert scan(package, "1.0.0", dir, [path]) == :ok

    assert scan_row = Repo.get_by(Scan, release_id: release.id)
    assert scan_row.finding_count == 0
    assert is_nil(scan_row.notified_at)
    assert SecretScan.findings(release) == []
  end

  test "mails the owners once, not on every rerun", %{dir: dir, package: package, user: user} do
    release = insert(:release, package: package, version: "1.0.0")
    path = write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")

    scan(package, "1.0.0", dir, [path])
    assert [finding] = SecretScan.findings(release)
    assert_outbox_email(package, "1.0.0", [finding], [user])

    # A second scan under a different checksum actually re-enters the
    # transaction, rather than short-circuiting at the already-scanned check.
    scan(package, "1.0.0", dir, [path], <<5, 5>>)
    assert outbox_count() == 1
    assert length(SecretScan.findings(release)) == 1
  end

  test "a rescan drops findings the new tarball no longer has", %{dir: dir, package: package} do
    release = insert(:release, package: package, version: "1.0.0")
    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])
    assert [_finding] = SecretScan.findings(release)

    File.rm!(Path.join(dir, ".env"))
    scan(package, "1.0.0", dir, [write(dir, "lib/app.ex", "defmodule App do\nend\n")], <<2>>)

    assert SecretScan.findings(release) == []
    assert Repo.get_by(Scan, release_id: release.id).finding_count == 0
  end

  test "a rescan moves a finding it still sees onto the new tarball", %{
    dir: dir,
    package: package
  } do
    release = insert(:release, package: package, version: "1.0.0")
    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])
    assert [finding] = SecretScan.findings(release)
    assert finding.tarball_checksum == @checksum

    File.rm!(Path.join(dir, ".env"))
    moved = write(dir, "config/prod.exs", ~s|t = "#{@github_token}"\n|)
    scan(package, "1.0.0", dir, [moved], <<9>>)

    assert [rescanned] = SecretScan.findings(release)
    assert rescanned.id == finding.id
    assert rescanned.tarball_checksum == <<9>>
    assert rescanned.file_path == "config/prod.exs"
    assert outbox_count() == 1
  end

  test "honours the package's secret_scan ignore metadata", %{package: package} do
    token = @github_token
    other = @other_token

    release =
      Hexpm.TestHelpers.insert_release_with_files(
        package,
        "1.0.0",
        [
          {"lib/app.ex", "T=#{token}\n"},
          {"test/fixtures/leak.env", "T=#{other}\n"}
        ],
        metadata: %{"secret_scan" => %{"ignore" => ["test/fixtures/**"]}}
      )

    SecretScan.scan_key("tarballs/#{package.name}-1.0.0.tar")

    # The fixture path is suppressed; only the source file's token is reported.
    assert [finding] = SecretScan.findings(release)
    assert finding.file_path == "lib/app.ex"
  end

  test "a package with no reachable owner records the scan and skips the mail", %{
    dir: dir,
    package: package
  } do
    release = insert(:release, package: package, version: "1.0.0")
    Repo.delete_all(Ecto.assoc(package, :package_owners))

    log =
      Hexpm.TestHelpers.capture_debug_log(fn ->
        scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])
      end)

    assert log =~ "no reachable owner"
    assert [_finding] = SecretScan.findings(release)
    assert Repo.get_by(Scan, release_id: release.id).finding_count == 1
    assert outbox_count() == 0
  end

  test "notified_at survives a rescan", %{dir: dir, package: package} do
    release = insert(:release, package: package, version: "1.0.0")
    path = write(dir, ".env", "T=#{@github_token}\n")

    scan(package, "1.0.0", dir, [path])
    notified_at = Repo.get_by(Scan, release_id: release.id).notified_at
    refute is_nil(notified_at)

    scan(package, "1.0.0", dir, [path], <<3>>)
    assert Repo.get_by(Scan, release_id: release.id).notified_at == notified_at
  end

  test "does nothing at all in read-only mode", %{dir: dir, package: package} do
    insert(:release, package: package, version: "1.0.0")
    path = write(dir, ".env", "T=#{@github_token}\n")

    Hexpm.TestHelpers.app_env(:hexpm, :read_only_mode, true)
    assert scan(package, "1.0.0", dir, [path]) == :ok

    assert Repo.all(Scan) == []
    assert Repo.all(Finding) == []
  end

  test "does not mail again for the same secret in a later version", %{
    dir: dir,
    package: package
  } do
    insert(:release, package: package, version: "1.0.0")
    path = write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")
    scan(package, "1.0.0", dir, [path])
    assert outbox_count() == 1

    second = insert(:release, package: package, version: "1.0.1")
    scan(package, "1.0.1", dir, [path], <<9, 9, 9>>)

    # Recorded against the new release, but not mailed twice.
    assert [_finding] = SecretScan.findings(second)
    assert outbox_count() == 1
  end

  test "mails again when a later version leaks something new", %{dir: dir, package: package} do
    insert(:release, package: package, version: "1.0.0")
    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])
    assert outbox_count() == 1

    insert(:release, package: package, version: "1.0.1")
    scan(package, "1.0.1", dir, [write(dir, ".env", "T=#{@other_token}\n")], <<9>>)
    assert outbox_count() == 2
  end

  test "rescans when the tarball changed under the same version", %{dir: dir, package: package} do
    release = insert(:release, package: package, version: "1.0.0")
    scan(package, "1.0.0", dir, [write(dir, "lib/app.ex", "defmodule App do\nend\n")])
    assert SecretScan.findings(release) == []

    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")], <<7, 7>>)
    assert [_finding] = SecretScan.findings(release)
  end

  test "records but does not mail when notification is off", %{dir: dir, package: package} do
    Application.put_env(:hexpm, :secret_scan_notify, false)
    release = insert(:release, package: package, version: "1.0.0")

    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])

    assert [_finding] = SecretScan.findings(release)
    assert outbox_count() == 0
    assert is_nil(Repo.get_by(Scan, release_id: release.id).notified_at)
  end

  test "records nothing for a non-notify rule", %{dir: dir, package: package} do
    release = insert(:release, package: package, version: "1.0.0")
    # A generic-api-key match, which is record-only and so not scanned in
    # production. The release records clean, not a silent finding.
    path = write(dir, "lib/app.ex", ~s|password = "123456789abcdefgh"\n|)

    scan(package, "1.0.0", dir, [path])

    assert SecretScan.findings(release) == []
    assert Repo.get_by(Scan, release_id: release.id).finding_count == 0
    assert outbox_count() == 0
  end

  test "mails the publisher as well as the owners", %{dir: dir, package: package, user: owner} do
    publisher = insert(:user)
    insert(:release, package: package, version: "1.0.0", publisher: publisher)

    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])

    assert [entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    addresses = Enum.map(entry.email["to"], & &1["address"])

    assert Hexpm.Accounts.User.email(Repo.preload(owner, :emails), :primary) in addresses
    assert Hexpm.Accounts.User.email(Repo.preload(publisher, :emails), :primary) in addresses
  end

  test "a private package notifies the org admins, whoever published it", %{dir: dir} do
    org = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: org, user: admin, role: "admin")

    # Published by a plain member with a personal key, so the package owner is
    # an individual and the org is nowhere in the ownership rows. The admin must
    # still be told.
    member = insert(:user)
    insert(:organization_user, organization: org, user: member, role: "write")
    repository = insert(:repository, organization: org, organization_id: org.id)

    package =
      insert(:package,
        repository_id: repository.id,
        package_owners: [build(:package_owner, user: member)]
      )

    insert(:release, package: package, version: "1.0.0", publisher: member)

    SecretScan.scan(
      repository.name,
      package.name,
      "1.0.0",
      dir,
      [write(dir, ".env", "T=#{@github_token}\n")],
      @checksum
    )

    assert [entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    addresses = Enum.map(entry.email["to"], & &1["address"])
    assert primary_email(admin) in addresses
    assert primary_email(member) in addresses
  end

  test "a public package owned by an org notifies its admins", %{dir: dir} do
    org = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: org, user: admin, role: "admin")

    package =
      insert(:package, package_owners: [build(:package_owner, user: org.user)])

    insert(:release, package: package, version: "1.0.0")

    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])

    assert [entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    addresses = Enum.map(entry.email["to"], & &1["address"])
    assert primary_email(admin) in addresses
  end

  test "emits a telemetry event with duration and finding count", %{dir: dir, package: package} do
    insert(:release, package: package, version: "1.0.0")
    ref = :telemetry_test.attach_event_handlers(self(), [[:hexpm, :secret_scan, :scan]])

    scan(package, "1.0.0", dir, [write(dir, ".env", "T=#{@github_token}\n")])

    assert_received {[:hexpm, :secret_scan, :scan], ^ref, measurements, %{truncated: false}}
    assert measurements.findings == 1
    assert is_integer(measurements.duration)
  end

  test "does nothing for a release that has gone", %{dir: dir, package: package} do
    assert scan(package, "9.9.9", dir, [write(dir, ".env", "T=#{@github_token}\n")]) == :ok
    assert Repo.all(Scan) == []
    assert Repo.all(Finding) == []
  end

  test "keeps the credential out of the email and the log", %{dir: dir, package: package} do
    insert(:release, package: package, version: "1.0.0")
    path = write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")

    log = Hexpm.TestHelpers.capture_debug_log(fn -> scan(package, "1.0.0", dir, [path]) end)
    refute log =~ @github_token

    assert [entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    refute entry.email["text_body"] =~ @github_token
    refute entry.email["html_body"] =~ @github_token
    assert entry.email["text_body"] =~ "ghp_************OU7Q"
  end

  defp primary_email(user), do: Hexpm.Accounts.User.email(Repo.preload(user, :emails), :primary)

  defp outbox_count, do: Repo.aggregate(Hexpm.Emails.OutboxEntry, :count)

  defp assert_outbox_email(package, version, findings, recipients) do
    assert [entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    assert entry.category == "secret_scan.findings"

    expected =
      recipients
      |> Enum.map(&Repo.preload(&1, :emails))
      |> Hexpm.Emails.secrets_detected(package.name, version, findings)

    assert entry.email["subject"] == expected.subject
    refute_email_sent()
  end
end
