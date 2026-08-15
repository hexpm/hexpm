defmodule Hexpm.SecretScan.WorkerTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.{Preview, SecretScan}
  alias Hexpm.SecretScan.Worker

  @github_token "ghp_" <> "016Cq2mKvXbNzR8dLpWyTuAeH3jFgS4iOU7Q"

  setup do
    notify = Application.get_env(:hexpm, :secret_scan_notify)
    Application.put_env(:hexpm, :secret_scan_notify, true)
    on_exit(fn -> Application.put_env(:hexpm, :secret_scan_notify, notify) end)

    user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])
    {:ok, package: package}
  end

  defp with_files(package, version, files) do
    Hexpm.TestHelpers.insert_release_with_files(package, version, files)
  end

  test "downloads, unpacks and scans the tarball at a key", %{package: package} do
    release =
      with_files(package, "1.0.0", [
        {"mix.exs", "defmodule App.MixProject do\nend\n"},
        {".env", "GITHUB_TOKEN=#{@github_token}\n"}
      ])

    assert SecretScan.scan_key("tarballs/#{package.name}-1.0.0.tar") == :ok

    assert [finding] = SecretScan.findings(release)
    assert finding.rule == "github-pat"
    assert finding.file_path == ".env"
    assert [entry] = Repo.all(Hexpm.Emails.OutboxEntry)
    assert entry.category == "secret_scan.findings"
  end

  test "runs from the Oban worker", %{package: package} do
    release = with_files(package, "1.0.0", [{".env", "GITHUB_TOKEN=#{@github_token}\n"}])

    assert :ok = perform_job(Worker, %{"key" => "tarballs/#{package.name}-1.0.0.tar"})
    assert [_finding] = SecretScan.findings(release)
  end

  test "scans a private organization package" do
    repository = insert(:repository)

    package =
      insert(:package,
        repository_id: repository.id,
        package_owners: [build(:package_owner, user: insert(:user))]
      )

    release = with_files(package, "1.0.0", [{".env", "GITHUB_TOKEN=#{@github_token}\n"}])

    key = "repos/#{repository.name}/tarballs/#{package.name}-1.0.0.tar"
    assert SecretScan.scan_key(key) == :ok
    assert [finding] = SecretScan.findings(release)
    assert finding.rule == "github-pat"
  end

  test "records a clean release", %{package: package} do
    release = with_files(package, "1.0.0", [{"mix.exs", "defmodule App.MixProject do\nend\n"}])

    assert SecretScan.scan_key("tarballs/#{package.name}-1.0.0.tar") == :ok
    assert SecretScan.findings(release) == []
    assert Repo.get_by(SecretScan.Scan, release_id: release.id).finding_count == 0
  end

  test "does nothing for a key whose release does not exist", %{package: package} do
    assert SecretScan.scan_key("tarballs/#{package.name}-9.9.9.tar") == :ok
    assert Repo.all(SecretScan.Scan) == []
  end

  test "the preview upload no longer scans", %{package: package} do
    with_files(package, "1.0.0", [{".env", "GITHUB_TOKEN=#{@github_token}\n"}])

    assert Preview.upload("tarballs/#{package.name}-1.0.0.tar") == :ok
    assert Repo.all(SecretScan.Scan) == []
    assert Repo.all(Hexpm.Emails.OutboxEntry) == []
  end

  test "does nothing in read-only mode without downloading", %{package: package} do
    with_files(package, "1.0.0", [{".env", "GITHUB_TOKEN=#{@github_token}\n"}])

    Hexpm.TestHelpers.app_env(:hexpm, :read_only_mode, true)
    assert SecretScan.scan_key("tarballs/#{package.name}-1.0.0.tar") == :ok
    assert Repo.all(SecretScan.Scan) == []
  end
end
