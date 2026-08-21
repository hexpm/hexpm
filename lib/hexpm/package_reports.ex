defmodule Hexpm.PackageReports do
  require Logger

  alias Hexpm.Accounts.User
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox
  alias Hexpm.PackageReports.{Maintainers, Report, Varsel}
  alias Hexpm.Repo

  def submit(package, %User{} = user, attrs) do
    changeset = Report.changeset(%Report{}, attrs)

    with {:ok, report} <- Ecto.Changeset.apply_action(changeset, :insert),
         reporter when not is_nil(reporter) <- Maintainers.identity(user) do
      report = insert_report(report, package, user)
      deliver(report, package, reporter)
    else
      {:error, changeset} -> {:error, changeset}
      nil -> {:error, :unverified_primary_email}
    end
  end

  defp deliver(%Report{reason: :vulnerability} = report, package, reporter) do
    result =
      Varsel.submit(%{
        summary: report.summary,
        description: report.description,
        maintainers: Maintainers.for_package(package),
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

  defp deliver(report, package, reporter) do
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
