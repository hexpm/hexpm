defmodule HexpmWeb.PackageReportController do
  use HexpmWeb, :controller

  plug :requires_login

  @sort_params ~w(timestamp)
  @new_report_msg "Package report generated"
  @report_updated_msg "Package report updated"
  @report_bad_update_msg "Package report can not be updated"
  @report_bad_version_msg "No release matchs given requirement"
  @report_not_accessible "Requested package report not accessible"

  def new_comment(conn, params) do
    report_id = params["id"]
    report = PackageReports.get(report_id)
    author = conn.assigns.current_user

    PackageReports.new_comment(%{
      "report" => report,
      "author" => author,
      "text" => params["text"]
    })

    redirect(conn, to: Routes.package_report_path(HexpmWeb.Endpoint, :show, report.id))
  end

  def index(conn, params) do
    reports = fetch_package_reports()
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
      conn
      |> put_flash(:error, @report_not_accessible)
      |> put_status(400)
      |> redirect(to: Routes.package_path(HexpmWeb.Endpoint, :index))
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
      |> new(%{"package" => package_name})
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
      |> redirect(to: Routes.package_report_path(HexpmWeb.Endpoint, :index))
    end
  end

  def show(conn, params) do
    report = PackageReports.get(params["id"])
    for_moderator = Users.has_role(conn.assigns.current_user, "moderator")
    user = conn.assigns.current_user
    for_owner = Owners.get(report.package, user) != nil

    if report == nil do
      conn
      |> put_flash(:error, @report_not_accessible)
      |> put_status(400)
      |> redirect(to: Routes.package_path(HexpmWeb.Endpoint, :index))
    else
      comments = PackageReports.all_comments_for_report(report.id)

      render(
        conn,
        "show.html",
        report: report,
        for_moderator: for_moderator,
        for_owner: for_owner,
        comments: comments
      )
    end
  end

  def accept_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    report = PackageReports.get(report_id)

    if valid_state_change("accepted", report) and
         Users.has_role(conn.assigns.current_user, "moderator") do
      PackageReports.accept(report_id, comment)
      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def reject_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    report = PackageReports.get(report_id)

    if valid_state_change("rejected", report) and
         Users.has_role(conn.assigns.current_user, "moderator") do
      PackageReports.reject(report_id, comment)
      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def solve_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    report = PackageReports.get(report_id)

    if valid_state_change("solved", report) and
         Users.has_role(conn.assigns.current_user, "moderator") do
      PackageReports.solve(report_id, comment)
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

  defp valid_state_change(new, %{state: "to_accept"}), do: new in ["accepted", "rejected"]
  defp valid_state_change(new, %{state: "accepted"}), do: new in ["solved", "rejected"]
  defp valid_state_change(new, _), do: false

  defp slice_releases(releases, requirement) do
    rs =
      Enum.filter(releases, fn r ->
        Version.match?(r.version, requirement)
      end)

    rs
  end

  defp fetch_package_reports() do
    PackageReports.all()
  end

  defp build_report_form(conn, params) do
    %{"repository" => repository, "package" => name} = params
    package = repository && Packages.get(repository, name)

    render(
      conn,
      "new_report.html",
      package_name: name,
      repository: repository
    )
  end
end
