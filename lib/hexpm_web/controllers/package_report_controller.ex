defmodule HexpmWeb.PackageReportController do
    use HexpmWeb, :controller

    @package_reports_per_page 4
    @sort_params ~w(timestamp)

    def index(conn, params) do
        reports = fetch_package_reports(@package_reports_per_page)
        count = PackageReports.count() 
       
        render(
            conn,
            "index.html",
            reports: reports,
            per_page: @package_reports_per_page,
            total: count
        )
    end

    def new(conn,params) do
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
        from_version = params["from_version"]
        to_version = params["to_version"]

        # TODO: build PackageReport and push to database
    end

    defp fetch_package_reports(count) do
        PackageReports.search(count)
    end

    defp fail_with(conn, msg) do
        conn
        |> put_flash(:error, msg)
        |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
    end

    defp build_report_form(conn,params) do
        %{"repository" => repository, "package" => name} = params
        package = repository && Packages.get(repository, name)
        releases = Releases.all(package)
        render(
            conn,
            "new_report.html",
            package_name: name,
            releases: releases
        )
    end
end