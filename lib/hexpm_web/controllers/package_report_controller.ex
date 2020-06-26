defmodule HexpmWeb.PackageReportController do
  use HexpmWeb, :controller

  plug :requires_login

  @sort_params ~w(timestamp)
  @new_report_msg "Package report generated"
  @report_updated_msg "Package report updated"
  @report_bad_update_msg "Package report can not be updated"
  @report_bad_version_msg "No release matchs given requirement"
  @report_not_accessible "Requested package report not accessible"

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
    to_moderator = Users.has_role(conn.assigns.current_user, "moderator")

    if report == nil or
         (report.state == "to_accept" and !to_moderator) do
      conn
      |> put_flash(:error, @report_not_accessible)
      |> put_status(400)
      |> redirect(to: Routes.package_path(HexpmWeb.Endpoint, :index))
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
      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def reject_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    report = PackageReports.get(report_id)

    if valid_state_change("rejected", report) do
      PackageReports.reject(conn, report_id, comment)
      notify_good_update(conn)
    else
      notify_bad_update(conn, %{"id" => report_id})
    end
  end

  def solve_report(conn, params) do
    report_id = params["report_id"]
    comment = params["comment"]

    report = PackageReports.get(report_id)

    if valid_state_change("solved", report) do
      PackageReports.solve(conn, report_id, comment)
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

  defp valid_state_change(state, report) do
    # TODO: check valid state change based on previous state and conn.user
    false
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
