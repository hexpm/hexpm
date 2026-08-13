defmodule HexpmWeb.PackageReportLiveTest do
  use HexpmWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Hexpm.Emails.OutboxEntry
  alias Hexpm.PackageReports.Report

  setup :verify_on_exit!

  setup do
    reporter = insert(:user, username: "reporter", full_name: "Report Person")
    maintainer = insert(:user, username: "maintainer", full_name: "Maintain Person")

    package =
      insert(:package,
        name: "reported_package",
        package_owners: [build(:package_owner, user: maintainer)]
      )

    %{reporter: reporter, package: package, conn: build_conn()}
  end

  test "requires a Hex user and returns to the form after login", %{conn: conn, package: package} do
    path = "/packages/#{package.name}/report"

    assert {:error, {:redirect, %{to: login_path}}} = live(conn, path)

    assert URI.decode_query(URI.parse(login_path).query) == %{"return" => path}
    assert URI.parse(login_path).path == "/login"
  end

  test "shows all reasons and only requires CNA confirmations for vulnerabilities", context do
    {:ok, view, _html} = live(test_login(context.conn, context.reporter), report_path(context))

    for {label, value} <- Hexpm.PackageReports.Report.reason_options() do
      assert has_element?(view, ~s(option[value="#{value}"]), label)
    end

    assert has_element?(view, "#vulnerability-confirmations")
    assert has_element?(view, "#package-report-captcha[data-sitekey=sitekey]")

    view
    |> form("#package-report-form", report: %{reason: "malware"})
    |> render_change()

    refute has_element?(view, "#vulnerability-confirmations")

    view
    |> form("#package-report-form",
      report: %{reason: "malware", summary: "", description: ""}
    )
    |> render_submit()

    assert has_element?(view, "#report_summary + div", "can't be blank")
    assert has_element?(view, "#report_description + div", "can't be blank")
  end

  test "submits vulnerabilities to Varsel and shows the returned report link", context do
    Mox.expect(Hexpm.PackageReports.Varsel.Mock, :submit, fn report ->
      assert report.package == context.package.name
      assert report.summary == "Unsafe parsing"
      assert report.description == "A crafted document can execute code."
      assert report.reporter.username == context.reporter.username
      assert Enum.map(report.maintainers, & &1.username) == ["maintainer"]

      {:ok,
       %{
         id: "report-id",
         url: "https://cna.erlef.org/reports/report-id",
         sign_in_url: "https://cna.erlef.org/sign-in/hex?return-url=/reports/report-id"
       }}
    end)

    {:ok, view, _html} = live(test_login(context.conn, context.reporter), report_path(context))
    Mox.allow(Hexpm.PackageReports.Varsel.Mock, self(), view.pid)
    allow_captcha(view, true)

    render_submit(view, "submit", %{
      "h-captcha-response" => "captcha",
      "report" => %{
        reason: "vulnerability",
        summary: "Unsafe parsing",
        description: "A crafted document can execute code.",
        confirms_criteria: true,
        confirms_in_scope: true
      }
    })

    assert has_element?(view, "#package-report-success", "Report submitted")

    assert has_element?(
             view,
             ~s(a[href="https://cna.erlef.org/sign-in/hex?return-url=/reports/report-id"]),
             "View report"
           )

    refute Repo.exists?(OutboxEntry)
  end

  test "keeps the report form when Varsel is unavailable", context do
    Mox.expect(Hexpm.PackageReports.Varsel.Mock, :submit, fn _report ->
      {:error, :unavailable}
    end)

    {:ok, view, _html} = live(test_login(context.conn, context.reporter), report_path(context))
    Mox.allow(Hexpm.PackageReports.Varsel.Mock, self(), view.pid)
    allow_captcha(view, true)

    render_submit(view, "submit", %{
      "h-captcha-response" => "captcha",
      "report" => %{
        reason: "vulnerability",
        summary: "Preserved summary",
        description: "Preserved details",
        confirms_criteria: true,
        confirms_in_scope: true
      }
    })

    assert render(view) =~ "The report couldn&#39;t be submitted. Please try again later."
    assert has_element?(view, ~s(input[name="report[summary]"][value="Preserved summary"]))
    assert has_element?(view, "textarea", "Preserved details")
    assert Repo.one!(Report).status == :failed
  end

  test "emails non-vulnerability reports to support and shows confirmation", context do
    {:ok, view, _html} = live(test_login(context.conn, context.reporter), report_path(context))
    allow_captcha(view, true)

    render_submit(view, "submit", %{
      "h-captcha-response" => "captcha",
      "report" => %{
        reason: "copyright_infringement",
        summary: "Copied source",
        description: "The package republishes copyrighted source."
      }
    })

    assert has_element?(view, "#package-report-success", "support@hex.pm")

    entry = Repo.one!(OutboxEntry)
    assert entry.email["to"] == [%{"name" => "", "address" => "support@hex.pm"}]

    assert entry.email["cc"] == [
             %{
               "name" => "Report Person",
               "address" => Hexpm.Accounts.User.email(context.reporter, :primary)
             }
           ]
  end

  test "rejects a report when hCaptcha verification fails", context do
    {:ok, view, _html} = live(test_login(context.conn, context.reporter), report_path(context))
    allow_captcha(view, false)

    render_submit(view, "submit", %{
      "h-captcha-response" => "captcha",
      "report" => %{
        reason: "other",
        summary: "Question",
        description: "Report details"
      }
    })

    assert has_element?(
             view,
             "#package-report-captcha-error",
             "Please complete the captcha to submit a package report."
           )

    refute Repo.exists?(Report)
    refute Repo.exists?(OutboxEntry)
  end

  test "allows organization members to report private packages", %{conn: conn, reporter: reporter} do
    repository = insert(:repository)

    insert(:organization_user,
      organization: repository.organization,
      user: reporter,
      role: "read"
    )

    package = insert(:package, repository_id: repository.id, name: "private_reported")
    path = "/packages/#{repository.name}/#{package.name}/report"

    assert {:ok, view, _html} = live(test_login(conn, reporter), path)
    assert has_element?(view, "h1", "Report package")
    assert has_element?(view, ~s(a[href="/packages/#{repository.name}/#{package.name}"]))
  end

  test "doesn't expose private packages to users without repository access", %{conn: conn} do
    repository = insert(:repository)
    package = insert(:package, repository_id: repository.id, name: "hidden_reported")
    outsider = insert(:user)

    assert_raise HexpmWeb.PackageReportLive.NotFoundError, fn ->
      live(
        test_login(conn, outsider),
        "/packages/#{repository.name}/#{package.name}/report"
      )
    end
  end

  defp report_path(%{package: package}), do: "/packages/#{package.name}/report"

  defp allow_captcha(view, success) do
    mock_captcha(success)
    Mox.allow(Hexpm.HTTP.Mock, self(), view.pid)
  end
end
