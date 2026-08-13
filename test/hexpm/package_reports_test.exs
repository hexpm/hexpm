defmodule Hexpm.PackageReportsTest do
  use Hexpm.DataCase, async: true

  import Mox

  alias Hexpm.Emails.OutboxEntry
  alias Hexpm.PackageReports
  alias Hexpm.PackageReports.{Maintainers, Report}

  setup :verify_on_exit!

  describe "Report.changeset/2" do
    test "requires vulnerability confirmations" do
      changeset =
        Report.changeset(%Report{}, %{
          reason: "vulnerability",
          summary: "Unsafe parsing",
          description: "Details"
        })

      assert errors_on(changeset).confirms_criteria == "must be confirmed"
      assert errors_on(changeset).confirms_in_scope == "must be confirmed"
    end

    test "accepts every supported reason without CNA confirmations" do
      for reason <- ~w(malware spam copyright_infringement other) do
        assert %{valid?: true} =
                 Report.changeset(%Report{}, %{
                   reason: reason,
                   summary: "Package report",
                   description: "Details"
                 })
      end
    end

    test "rejects line breaks in the email subject summary" do
      changeset =
        Report.changeset(%Report{}, %{
          reason: "other",
          summary: "First line\nBcc: attacker@example.com",
          description: "Details"
        })

      assert errors_on(changeset).summary == "must be one line"
    end
  end

  describe "submit/3" do
    test "sends vulnerability reports to Varsel" do
      reporter = insert(:user, username: "reporter", full_name: "Report Person")
      maintainer = insert(:user, username: "maintainer", full_name: "Maintain Person")

      package =
        insert(:package,
          name: "reported_package",
          package_owners: [build(:package_owner, user: maintainer)]
        )

      expect(Hexpm.PackageReports.Varsel.Mock, :submit, fn report ->
        assert report == %{
                 summary: "Unsafe parsing",
                 description: "A crafted document can execute code.",
                 package: "reported_package",
                 maintainers: [
                   %{
                     name: "Maintain Person",
                     username: "maintainer",
                     email: Hexpm.Accounts.User.email(maintainer, :primary)
                   }
                 ],
                 reporter: %{
                   name: "Report Person",
                   username: "reporter",
                   email: Hexpm.Accounts.User.email(reporter, :primary)
                 }
               }

        {:ok,
         %{
           id: "report-id",
           url: "https://cna.erlef.org/reports/report-id",
           sign_in_url: "https://cna.erlef.org/sign-in/hex?return-url=/reports/report-id"
         }}
      end)

      assert {:ok, %{id: "report-id"}} =
               PackageReports.submit(package, reporter, %{
                 reason: "vulnerability",
                 summary: "Unsafe parsing",
                 description: "A crafted document can execute code.",
                 confirms_criteria: "true",
                 confirms_in_scope: "true"
               })

      saved_report = Repo.one!(Report)

      assert saved_report.reason == :vulnerability
      assert saved_report.summary == "Unsafe parsing"
      assert saved_report.description == "A crafted document can execute code."
      assert saved_report.status == :submitted
      assert saved_report.package_id == package.id
      assert saved_report.reporter_id == reporter.id
      assert saved_report.external_id == "report-id"
      assert saved_report.external_url == "https://cna.erlef.org/reports/report-id"

      assert saved_report.external_sign_in_url ==
               "https://cna.erlef.org/sign-in/hex?return-url=/reports/report-id"

      refute Repo.exists?(OutboxEntry)
    end

    test "records failed vulnerability delivery attempts" do
      reporter = insert(:user)
      package = insert(:package)

      expect(Hexpm.PackageReports.Varsel.Mock, :submit, fn _report ->
        {:error, :unavailable}
      end)

      assert {:error, :unavailable} =
               PackageReports.submit(package, reporter, %{
                 reason: "vulnerability",
                 summary: "Unsafe parsing",
                 description: "Details",
                 confirms_criteria: "true",
                 confirms_in_scope: "true"
               })

      assert %Report{
               reason: :vulnerability,
               status: :failed,
               package_id: package_id,
               reporter_id: reporter_id,
               external_id: nil
             } = Repo.one!(Report)

      assert package_id == package.id
      assert reporter_id == reporter.id
    end

    test "queues other reports to support and copies the reporter" do
      reporter = insert(:user, username: "reporter", full_name: "Report Person")
      package = insert(:package, name: "spam_package")

      assert {:ok, :email} =
               PackageReports.submit(package, reporter, %{
                 reason: "spam",
                 summary: "Generated package",
                 description: "The package contains generated advertisements."
               })

      entry = Repo.one!(OutboxEntry)
      saved_report = Repo.one!(Report)
      email = entry.email
      reporter_email = Hexpm.Accounts.User.email(reporter, :primary)

      assert saved_report.reason == :spam
      assert saved_report.status == :submitted
      assert saved_report.package_id == package.id
      assert saved_report.reporter_id == reporter.id
      assert entry.category == "package.report"
      assert entry.group_key == "package-report:#{saved_report.id}"
      assert entry.scope_key == "package:#{package.id}"
      assert email["to"] == [%{"name" => "", "address" => "support@hex.pm"}]
      assert email["cc"] == [%{"name" => "Report Person", "address" => reporter_email}]
      assert email["reply_to"] == %{"name" => "Report Person", "address" => reporter_email}
      assert email["subject"] == "Hex.pm package report: Generated package"
      assert email["text_body"] =~ "Reason: Spam"
      assert email["text_body"] =~ "http://localhost:5000/packages/spam_package"
    end

    test "rejects a reporter without a verified primary email" do
      reporter =
        insert(:user,
          emails: [build(:email, primary: true, verified: false)]
        )

      assert {:error, :unverified_primary_email} =
               PackageReports.submit(insert(:package), reporter, %{
                 reason: "other",
                 summary: "Question",
                 description: "Details"
               })

      refute Repo.exists?(OutboxEntry)
      refute Repo.exists?(Report)
    end
  end

  describe "Maintainers.for_package/1" do
    test "expands public organization owners to admins and filters unverified addresses" do
      organization = insert(:organization)
      admin = insert(:user, username: "org_admin", full_name: "Org Admin")
      member = insert(:user, username: "org_member")
      direct = insert(:user, username: "direct_owner", full_name: nil)

      unverified =
        insert(:user,
          username: "unverified_owner",
          emails: [build(:email, primary: true, verified: false)]
        )

      insert(:organization_user, organization: organization, user: admin, role: "admin")
      insert(:organization_user, organization: organization, user: member, role: "read")

      package =
        insert(:package,
          package_owners: [
            build(:package_owner, user: direct),
            build(:package_owner, user: organization.user),
            build(:package_owner, user: unverified)
          ]
        )

      maintainers = Maintainers.for_package(package)

      assert MapSet.new(maintainers, & &1.username) == MapSet.new(["direct_owner", "org_admin"])
      assert Enum.find(maintainers, &(&1.username == "direct_owner")).name == "direct_owner"
      refute Enum.any?(maintainers, &(&1.username == member.username))
      refute Enum.any?(maintainers, &(&1.username == unverified.username))
    end

    test "includes private repository admins even without package ownership" do
      repository = insert(:repository)
      admin = insert(:user, username: "private_admin")
      member = insert(:user, username: "private_member")
      direct = insert(:user, username: "private_owner")

      insert(:organization_user,
        organization: repository.organization,
        user: admin,
        role: "admin"
      )

      insert(:organization_user,
        organization: repository.organization,
        user: member,
        role: "read"
      )

      package =
        insert(:package,
          repository: repository,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: direct)]
        )

      assert package
             |> Maintainers.for_package()
             |> Enum.map(& &1.username)
             |> MapSet.new() == MapSet.new(["private_admin", "private_owner"])
    end

    test "uses all organization members when an organization has no admins" do
      organization = insert(:organization)
      writer = insert(:user, username: "org_writer")
      reader = insert(:user, username: "org_reader")

      insert(:organization_user, organization: organization, user: writer, role: "write")
      insert(:organization_user, organization: organization, user: reader, role: "read")

      package =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user)]
        )

      assert package
             |> Maintainers.for_package()
             |> Enum.map(& &1.username)
             |> MapSet.new() == MapSet.new(["org_reader", "org_writer"])
    end

    test "falls back to members when no admin has a verified primary email" do
      organization = insert(:organization)

      admin =
        insert(:user,
          username: "unverified_admin",
          emails: [build(:email, primary: true, verified: false)]
        )

      member = insert(:user, username: "verified_member")
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      insert(:organization_user, organization: organization, user: member, role: "read")

      package =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user)]
        )

      assert [%{username: "verified_member"}] = Maintainers.for_package(package)
    end
  end
end
