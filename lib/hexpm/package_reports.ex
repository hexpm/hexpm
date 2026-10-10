defmodule Hexpm.PackageReports do
  require Logger

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Hexpm.Accounts.User
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox
  alias Hexpm.PackageReports.{Disclosure, ErasureWorker, Maintainers, Report, Varsel}
  alias Hexpm.Repo

  def submit(package, %User{} = user, attrs) do
    changeset = Report.changeset(%Report{}, attrs)

    with {:ok, report} <- Ecto.Changeset.apply_action(changeset, :insert),
         reporter when not is_nil(reporter) <- Maintainers.identity(user) do
      report = insert_report(report, package, user)
      deliver(report, package, user, reporter)
    else
      {:error, changeset} -> {:error, changeset}
      nil -> {:error, :unverified_primary_email}
    end
  end

  defp deliver(%Report{reason: :vulnerability} = report, package, user, reporter) do
    maintainers = Maintainers.users(package)
    record_disclosure([user | maintainers])

    result =
      Varsel.submit(%{
        summary: report.summary,
        description: report.description,
        maintainers: Enum.map(maintainers, &Maintainers.identity/1),
        reporter: reporter,
        package: package_identifier(package)
      })

    case result do
      {:ok, external_report} ->
        update_report(report,
          status: :submitted,
          external_id: external_report.id,
          external_url: external_report.url,
          external_sign_in_url: external_report.sign_in_url
        )

        result

      {:error, :unavailable} ->
        update_report(report, status: :failed)
        result
    end
  end

  defp deliver(report, package, _user, reporter) do
    email =
      Emails.package_report(
        package_identifier(package),
        package_url(package),
        report,
        reporter
      )

    outbox_attrs =
      Outbox.prepare!(email,
        category: "package.report",
        group_key: "package-report:#{report.id}",
        scope_key: "package:#{package.id}"
      )

    Repo.transaction(fn ->
      Outbox.insert!(outbox_attrs)
      update_report(report, status: :submitted)
    end)

    {:ok, :email}
  rescue
    error ->
      update_report(report, status: :failed)
      Logger.error("Package report email enqueue failed: #{inspect(error.__struct__)}")
      {:error, :unavailable}
  end

  @doc """
  Records that these users' personal data is about to be sent to the CNA.

  Called before the data is sent, so a response that never arrives still
  leaves the record. The insert waits on the users' rows, which
  `notify_erasure/2` locks while a deletion runs, and fails once a user is
  deleted, so the data is never sent for a user whose deletion missed the
  record.
  """
  def record_disclosure(users) do
    now = DateTime.utc_now()

    rows =
      users
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&%{user_id: &1.id, inserted_at: now})

    Repo.insert_all(Disclosure, rows, on_conflict: :nothing, conflict_target: :user_id)
  end

  @doc """
  Adds a notice to the CNA to the transaction that deletes `user`, when hex.pm
  has sent the CNA the user's personal data.
  """
  def notify_erasure(multi, %User{} = user) do
    Multi.run(multi, :varsel_erasure, fn repo, _changes ->
      repo.one!(from(u in User, where: u.id == ^user.id, select: u.id, lock: "FOR UPDATE"))

      if repo.exists?(from(d in Disclosure, where: d.user_id == ^user.id)) do
        Oban.insert(ErasureWorker.new_job(user))
      else
        {:ok, nil}
      end
    end)
  end

  defp insert_report(report, package, user) do
    report
    |> Ecto.Changeset.change(
      status: :pending,
      package_id: package.id,
      reporter_id: user.id
    )
    |> Repo.insert!(log: false)
  end

  defp update_report(report, attrs) do
    report
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!(log: false)
  end

  def package_identifier(%{repository_id: 1, name: name}), do: name

  def package_identifier(%{repository: repository, name: name}),
    do: "#{repository.name}/#{name}"

  def package_path(%{repository_id: 1, name: name}), do: "/packages/#{name}"

  def package_path(%{repository: repository, name: name}),
    do: "/packages/#{repository.name}/#{name}"

  def report_path(package), do: package_path(package) <> "/report"

  defp package_url(package) do
    HexpmWeb.EmailView.email_url(package_path(package))
  end
end
