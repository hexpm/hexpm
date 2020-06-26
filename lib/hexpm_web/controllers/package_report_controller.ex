defmodule HexpmWeb.PackageReportController do
  use HexpmWeb, :controller

  plug :requires_login

  @sort_params ~w(timestamp)
  @new_report_msg "Package report generated"
  @report_updated_msg "Package report updated"
  @report_bad_update_msg "Package report can not be updated"
  @report_bad_version_msg "No release matchs given requirement"

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

    if conn.assigns.current_user do
      if package do
        build_report_form(conn, params)
      else
        fail_with(conn, "No package selected.")
      end
    else
      fail_with(conn, "Need to be logged to submit a report.")
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
      |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
    else 
      %{
        "package" => package,
        "releases" => report_releases,
        "user" => user,
        "description" => description,
        "state" => state
      }
      |> PackageReports.add()
    end    
  end

  def show(conn, params) do
    report = PackageReports.get(params["id"])
    to_moderator = Users.has_role(conn.assigns.current_user, "moderator")

    if report == nil or
         (report.state == "to_accept" and !to_moderator) do
      fail_with(conn, "Requested report not available.")
    else
      render(
        conn,
        "show.html",
        report: report,
        to_moderator: to_moderator
      )
    end
  end

  def accept_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    report = PackageReports.get(report_id)

    if valid_state_change("accepted", report) do
      PackageReports.accept(conn, report_id, comment)
      notify_good_update()
    else
      notify_bad_update()
  end

  def reject_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    if valid_state_change("rejected", report) do
      PackageReports.reject(conn, report_id, comment)
      notify_good_update()
    else
      notify_bad_update()
  end

  def solve_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    if valid_state_change("solved", report) do
      PackageReports.solve(conn, report_id, comment)
      notify_good_update()
    else
      notify_bad_update()
  end

  defp notify_good_update() do
      conn
      |> put_flash(:info, @report_updated_msg)
      |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end
  
  defp notify_bad_update() do
    conn
    |> put_flash(:error, @report_badupdate_msg)
    |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end

  defp valid_state_change(state, report) do
    # TODO: check valid state change based on conn.user too
    true
  end

  defp slice_releases(releases, requirement) do
    rs =
      Enum.filter(releases, fn r ->
        Version.match?(r.version, requirement)
      end)
    rs
  end

  defp clean_dots(version) do
    String.replace("#{version}", ".", "")
  end

  defp fetch_package_reports() do
    PackageReports.all()
  end

  defp fail_with(conn, msg) do
    conn
    |> put_flash(:error, msg)
    |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end

  defp build_report_form(conn, params) do
    %{"repository" => repository, "package" => name} = params
    package = repository && Packages.get(repository, name)

    render(
      conn,
      "new_report.html",
      package_name: name,
      repository: repository,
    )
  end
end
