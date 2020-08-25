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

    Enum.each(
      Users.get_by_role("moderator"),
      &email_user_about_new_report(package_report, &1)
    )

    package_report
  end

  def all() do
    PackageReport.all()
    |> Repo.all()
  end

  def count() do
    PackageReport.count()
    |> Repo.one()
  end

  def get(id) do
    PackageReport.get(id)
    |> Repo.one()
  end

  def accept(report_id) do
    PackageReport.get(report_id)
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "accepted"})
    |> Repo.update()

    report = Repo.one(PackageReport.get(report_id))

    Enum.each(
      Enum.map(Owners.all(report.package, user: []), & &1.user) ++
        [report.author] ++ Users.get_by_role("moderator"),
      &email_user_about_state_change(report, &1)
    )
  end

  def reject(report_id) do
    PackageReport.get(report_id)
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "rejected"})
    |> Repo.update()

    report = Repo.one(PackageReport.get(report_id))

    Enum.each(
      [report.author] ++ Users.get_by_role("moderator"),
      &email_user_about_state_change(report, &1)
    )
  end

  def solve(report_id) do
    report = PackageReport.get(report_id)

    report
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "solved"})
    |> Repo.update()

    report = Repo.one(PackageReport.get(report_id))

    Enum.each(report.releases, fn r ->
      PackageReports.mark_release(r)
    end)

    Enum.each(
      Enum.map(Owners.all(report.package, user: []), & &1.user) ++ Users.get_by_role("moderator"),
      &email_user_about_state_change(report, &1)
    )
  end

  def unresolve(report_id) do
    report = PackageReport.get(report_id)

    report
    |> Repo.one()
    |> PackageReport.change_state(%{"state" => "unresolved"})
    |> Repo.update()

    report = Repo.one(PackageReport.get(report_id))

    Enum.each(report.releases, fn r ->
      PackageReports.mark_release(r)
    end)

    Enum.each(
      Enum.map(Owners.all(report.package, [:user]), & &1.user) ++ Users.get_by_role("moderator"),
      &email_user_about_state_change(report, &1)
    )
  end

  def new_comment(params) do
    comment = Repo.insert(PackageReportComment.build(params["report"], params["author"], params))
    comment = Hexpm.Repo.preload(Kernel.elem(comment, 1), report: [])

    Enum.each(
      Enum.map(Owners.all(comment.report.package, user: []), & &1.user) ++
        [comment.report.author] ++ Users.get_by_role("moderator"),
      &email_user_about_new_comment(comment, &1)
    )

    comment
  end

  def count_comments(report_id) do
    PackageReportComment.count(report_id)
    |> Repo.one()
  end

  def all_comments_for_report(report_id) do
    PackageReportComment.all_for_report(report_id)
    |> Repo.all()
  end

  def mark_release(release) do
    Release.reported_retire(release)
    |> Repo.update!()
  end

  defp email_user_about_new_report(package_report, user) do
    user
    |> Hexpm.Repo.preload(emails: [])
    |> Emails.report_submitted(
      package_report.author.username,
      package_report.package.name,
      package_report.id,
      package_report.inserted_at
    )
    |> Mailer.deliver_now_throttled()
  end

  defp email_user_about_new_comment(comment, user) do
    user
    |> Hexpm.Repo.preload(emails: [])
    |> Emails.report_commented(
      comment.author.username,
      comment.report.id,
      comment.inserted_at
    )
    |> Mailer.deliver_now_throttled()
  end

  defp email_user_about_state_change(package_report, user) do
    user
    |> Hexpm.Repo.preload(emails: [])
    |> Emails.report_state_changed(
      package_report.id,
      package_report.state,
      package_report.updated_at
    )
    |> Mailer.deliver_now_throttled()
  end
end
