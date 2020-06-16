defmodule HexpmWeb.PackageReportController do
    use HexpmWeb, :controller

    @package_reports_per_page 30
    @sort_params ~w(timestamp)
    @new_report_msg "Package report generated"
    @report_updated_msg "Package report updated"

    def index(conn, params) do
        page_param = Hexpm.Utils.safe_int(params["page"]) || 1
        reports = fetch_package_reports(@package_reports_per_page, page_param, conn.assigns.current_user)
        reports_count = Enum.count(reports)
        page = Hexpm.Utils.safe_page(page_param, reports_count, @packages_per_page)
        
        
        render(
            conn,
            "index.html",
            reports: reports,
            per_page: @package_reports_per_page,
            page: page,
            total: reports_count
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
        package_name = params["package"]
        state = "to_accept"
        from_version = params["from_version"]
        to_version = params["to_version"]
        repository = params["repository"]

        package = Packages.get(repository,package_name)
        
        user = conn.assigns.current_user
        all_releases = Releases.all(package)

        %{
            "package" => package,
            "releases" => slice_releases(all_releases, from_version, to_version),
            "user" => user,
            "description" => description,
            "state" => state
        }
        |> PackageReports.add()    
        
        conn
        |> put_flash(:info, @new_report_msg)
        |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
    end

    def show(conn, params) do
        report = PackageReports.get(params["id"])
        to_moderator = Users.has_role(conn.assigns.current_user, "moderator")

        if report == nil or
        (report.state == "to_accept" and !to_moderator)
        do
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

    def mod_review(conn, params) do
        report_id = params["report_id"]
        comment = params["comment"]
        operation = String.downcase(params["operation"])
        
        new_state = case operation do
            "accept" -> "accepted"
            "reject" -> "rejected"
        end

        report = PackageReports.get(report_id)

        PackageReports.change_state(report, comment, new_state )

        conn
        |> put_flash(:info, @report_updated_msg)
        |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
    end

    defp slice_releases(releases, from, to) do
        a = Enum.filter(releases, fn r -> 
            clean_dots(r.version) >= clean_dots(from) 
            && clean_dots(r.version) <= clean_dots(to) 
        end)
        a    
    end

    defp clean_dots(version) do
        String.replace("#{version}",".","")
    end

    defp fetch_package_reports(count, page, user) do
        if Users.has_role(user, "moderator") do
            PackageReports.search(count, page, nil)
        else
            PackageReports.search(
                        count, 
                        page,
                        "state:not_equal:to_accept"
                    )
        end
    end

    defp fail_with(conn, msg) do
        conn
        |> put_flash(:error, msg)
        |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
    end

    defp build_report_form(conn, params) do
        %{"repository" => repository, "package" => name} = params
        package = repository && Packages.get(repository, name)
        releases = Releases.all(package)
        render(
            conn,
            "new_report.html",
            package_name: name,
            repository: repository,
            releases: releases
        )
    end
end