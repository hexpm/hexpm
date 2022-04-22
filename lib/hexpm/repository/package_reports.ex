defmodule Hexpm.Repository.PackageReports do
  use Hexpm.Context

  def add(params) do
    package_report =
      Repo.insert!(
        PackageReport.build(
          params["releases"],
          params["user"],
          params["package"],
          params
        )
      )

    Enum.each(Users.get_by_role("moderator"), &email_new_report(package_report, &1))

    package_report
  end

  def all() do
    PackageReport.all()
    |> Repo.all()
  end

  def get(id) do
    PackageReport.get(id)
    |> Repo.one()
  end

  def accept(report_id) do
    report =
      PackageReport.get(report_id)
      |> Repo.one()
      |> PackageReport.change_state(%{"state" => "accepted"})
      |> Repo.update!()

    users =
      Enum.map(Owners.all(report.package, [:user]), & &1.user) ++
        [report.author] ++
        Users.get_by_role("moderator")

    Enum.each(users, &email_state_change(report, &1))
  end

  def reject(report_id) do
    report =
      PackageReport.get(report_id)
      |> Repo.one()
      |> PackageReport.change_state(%{"state" => "rejected"})
      |> Repo.update!()

    Enum.each(
      [report.author] ++ Users.get_by_role("moderator"),
      &email_state_change(report, &1)
    )
  end

  def solve(report_id) do
    report =
      PackageReport.get(report_id)
      |> Repo.one()
      |> PackageReport.change_state(%{"state" => "solved"})
      |> Repo.update!()

    Enum.each(report.releases, &mark_release/1)

    users =
      Enum.map(Owners.all(report.package, [:user]), & &1.user) ++
        Users.get_by_role("moderator")

    Enum.each(users, &email_state_change(report, &1))
  end

  def unresolve(report_id) do
    report =
      PackageReport.get(report_id)
      |> Repo.one()
      |> PackageReport.change_state(%{"state" => "unresolved"})
      |> Repo.update!()

    Enum.each(report.releases, &PackageReports.mark_release/1)

    users =
      Enum.map(Owners.all(report.package, [:user]), & &1.user) ++ Users.get_by_role("moderator")

    Enum.each(users, &email_state_change(report, &1))
  end

  def new_comment(report, author, params) do
    comment = Repo.insert!(PackageReportComment.build(report, author, params))

    users =
      Enum.map(Owners.all(report.package, [:user]), & &1.user) ++
        [author] ++
        Users.get_by_role("moderator")

    Enum.each(users, &email_new_comment(comment, report, &1))

    comment
  end

  def all_comments(report_id) do
    PackageReportComment.all_for_report(report_id)
    |> Repo.all()
  end

  def mark_release(release) do
    Release.reported_retire(release)
    |> Repo.update!()
  end

  defp email_new_report(package_report, user) do
    user
    |> Hexpm.Repo.preload([:emails])
    |> Emails.report_submitted(
      package_report.author.username,
      package_report.package.name,
      package_report.id,
      package_report.inserted_at
    )
    |> Mailer.deliver_later!()
  end

  defp email_new_comment(comment, report, user) do
    user
    |> Hexpm.Repo.preload([:emails])
    |> Emails.report_commented(
      comment.author.username,
      report.id,
      comment.inserted_at
    )
    |> Mailer.deliver_later!()
  end

  defp email_state_change(package_report, user) do
    user
    |> Hexpm.Repo.preload([:emails])
    |> Emails.report_state_changed(
      package_report.id,
      package_report.state,
      package_report.updated_at
    )
    |> Mailer.deliver_later!()
  end
end
