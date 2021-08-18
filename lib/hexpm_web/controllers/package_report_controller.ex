defmodule HexpmWeb.PackageReportController do
  use HexpmWeb, :controller

  plug :requires_login

  @new_report_msg "Package report generated"
  @report_updated_msg "Package report updated"
  @report_bad_update_msg "Package report can not be updated"
  @report_bad_version_msg "No release matches given requirement"

  def new_comment(conn, params) do
    report = PackageReports.get(params["id"])
    author = conn.assigns.current_user
    PackageReports.new_comment(report, author, params)

    redirect(conn, to: Routes.package_report_path(HexpmWeb.Endpoint, :show, report.id))
  end

  def index(conn, _params) do
    reports = PackageReports.all()
    reports_count = Enum.count(reports)

    render(
      conn,
      "index.html",
      reports: reports,
      total: reports_count
    )
  end

  def new(conn, params) do
    package = params["package"]

    if package do
      build_report_form(conn, params)
    else
      not_found(conn)
    end
  end

  def create(conn, params) do
    description = params["description"]
    package_name = params["package"]
    state = "to_accept"
    requirement = params["requirement"]
    repository = params["repository"]

    package = Packages.get(repository, package_name)

    user = conn.assigns.current_user
    all_releases = Releases.all(package)

    report_releases = slice_releases(all_releases, requirement)

    if report_releases == [] do
      conn
      |> put_flash(:error, @report_bad_version_msg)
      |> put_status(400)
      |> new(%{
        "repository" => repository,
        "package" => package_name,
        "description" => description
      })
    else
      %{
        "package" => package,
        "releases" => report_releases,
        "user" => user,
        "description" => description,
        "state" => state
      }
      |> PackageReports.add()

      conn
      |> put_flash(:info, @new_report_msg)
      |> redirect(to: Routes.package_report_path(HexpmWeb.Endpoint, :index))
    end
  end

  def show(conn, params) do
    report = PackageReports.get(params["id"])
    user = conn.assigns.current_user

    if report do
      for_moderator = User.has_role?(user, "moderator")
      for_owner = Owners.get(report.package, user) != nil
      for_author = user.id == report.author.id

      if visible_report?(report, user, for_owner) do
        comments = PackageReports.all_comments(report.id)

        render(
          conn,
          "show.html",
          report: report,
          for_moderator: for_moderator,
          for_owner: for_owner,
          for_author: for_author,
          comments: comments
        )
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  defp visible_report?(report, user, owner?) do
    moderator? = User.has_role?(user, "moderator")
    author? = user.id == report.author.id

    cond do
      report.state in ["to_accept", "rejected"] -> moderator? or author?
      report.state == "accepted" -> moderator? or author? or owner?
      report.state in ["solved", "unresolved"] -> true
    end
  end

  def accept_report(conn, params) do
    report_id = params["id"]

    report = PackageReports.get(report_id)

    if valid_state_change?("accepted", report) and
         User.has_role?(conn.assigns.current_user, "moderator") do
      PackageReports.accept(report_id)
      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def reject_report(conn, params) do
    report_id = params["id"]

    report = PackageReports.get(report_id)

    if valid_state_change?("rejected", report) and
         User.has_role?(conn.assigns.current_user, "moderator") do
      PackageReports.reject(report_id)

      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def solve_report(conn, params) do
    report_id = params["id"]

    report = PackageReports.get(report_id)

    if valid_state_change?("solved", report) and
         User.has_role?(conn.assigns.current_user, "moderator") do
      PackageReports.solve(report_id)

      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def unresolve_report(conn, params) do
    report_id = params["id"]

    report = PackageReports.get(report_id)

    if valid_state_change?("unresolved", report) and
         User.has_role?(conn.assigns.current_user, "moderator") do
      PackageReports.unresolve(report_id)

      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  defp notify_good_update(conn) do
    conn
    |> put_flash(:info, @report_updated_msg)
    |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end

  defp notify_bad_update(conn, params) do
    conn
    |> put_flash(:error, @report_bad_update_msg)
    |> put_status(400)
    |> show(params)
  end

  defp valid_state_change?(new, %{state: "to_accept"}), do: new in ["accepted", "rejected"]

  defp valid_state_change?(new, %{state: "accepted"}),
    do: new in ["solved", "rejected", "unresolved"]

  defp valid_state_change?(new, %{state: "rejected"}), do: new in ["accepted"]
  defp valid_state_change?(_new, _), do: false

  defp slice_releases(releases, requirement) do
    case Version.parse_requirement(requirement) do
      {:ok, requirement} ->
        Enum.filter(releases, &Version.match?(&1.version, requirement))

      :error ->
        []
    end
  end

  defp build_report_form(conn, params) do
    %{"repository" => repository, "package" => name} = params
    description = params["description"]

    render(
      conn,
      "new_report.html",
      package_name: name,
      repository: repository,
      description: description
    )
  end
end
