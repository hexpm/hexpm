defmodule Hexpm.Repository.PackageReportsTests do
  use Hexpm.DataCase, async: true
  use Bamboo.Test

  alias Hexpm.Repository.PackageReports
  alias Hexpm.Repository.Packages
  alias Hexpm.Repository.Repository

  setup do
    hexpm = Hexpm.Repo.get(Repository, 1)
    description = "this is a generic valid description for tests"

    author = insert(:user)
    moderator = insert(:user, role: "moderator")
    owner = insert(:user)
    other_user = insert(:user)

    owners = [build(:package_owner, user: owner)]
    package = %{insert(:package, package_owners: owners) | repository: Repository.hexpm()}
    release = insert(:release, package: package, version: "0.1.0")

    %{
      repository: hexpm,
      package: package,
      release: release,
      author: author,
      moderator: moderator,
      description: description,
      owner: owner,
      other_user: other_user
    }
  end

  describe "add/2" do
    test "check valid state set and emails sent", %{
      package: package,
      release: release,
      author: author,
      moderator: moderator,
      description: description
    } do
      report =
        PackageReports.add(%{
          "releases" => [release],
          "user" => author,
          "package" => package,
          "description" => description
        })

      assert report.state == "to_accept"

      assert_delivered_email(
        Hexpm.Emails.report_submitted(
          moderator,
          report.author.username,
          report.package.name,
          report.id,
          report.inserted_at
        )
      )
    end
  end

  describe "accept/2" do
    test "check emails sent", %{
      package: package,
      release: release,
      owner: owner,
      author: author,
      moderator: moderator,
      description: description
    } do
      id =
        PackageReports.add(%{
          "releases" => [release],
          "user" => author,
          "package" => package,
          "description" => description
        }).id

      PackageReports.accept(id)
      report = PackageReports.get(id)

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          owner,
          report.id,
          "accepted",
          report.updated_at
        )
      )

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          author,
          report.id,
          "accepted",
          report.updated_at
        )
      )

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          moderator,
          report.id,
          "accepted",
          report.updated_at
        )
      )
    end
  end

  describe "reject/2" do
    test "check emails sent", %{
      package: package,
      release: release,
      author: author,
      moderator: moderator,
      description: description
    } do
      id =
        PackageReports.add(%{
          "releases" => [release],
          "user" => author,
          "package" => package,
          "description" => description
        }).id

      PackageReports.reject(id)
      report = PackageReports.get(id)

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          author,
          report.id,
          "rejected",
          report.updated_at
        )
      )

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          moderator,
          report.id,
          "rejected",
          report.updated_at
        )
      )
    end
  end

  describe "solve/2" do
    test "check emails sent", %{
      package: package,
      release: release,
      owner: owner,
      author: author,
      moderator: moderator,
      description: description
    } do
      id =
        PackageReports.add(%{
          "releases" => [release],
          "user" => author,
          "package" => package,
          "description" => description
        }).id

      PackageReports.accept(id)
      PackageReports.solve(id)
      report = PackageReports.get(id)

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          owner,
          report.id,
          "solved",
          report.updated_at
        )
      )

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          moderator,
          report.id,
          "solved",
          report.updated_at
        )
      )
    end
  end

  describe "unresolve/1" do
    test "check emails sent", %{
      package: package,
      release: release,
      owner: owner,
      author: author,
      moderator: moderator,
      description: description
    } do
      id =
        PackageReports.add(%{
          "releases" => [release],
          "user" => author,
          "package" => package,
          "description" => description
        }).id

      PackageReports.accept(id)
      PackageReports.unresolve(id)
      report = PackageReports.get(id)

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          owner,
          report.id,
          "unresolved",
          report.updated_at
        )
      )

      assert_delivered_email(
        Hexpm.Emails.report_state_changed(
          moderator,
          report.id,
          "unresolved",
          report.updated_at
        )
      )
    end
  end

  describe "new_comment/1" do
    test "check emails sent", %{
      package: package,
      release: release,
      author: author,
      moderator: moderator,
      other_user: other_user,
      description: description
    } do
      id =
        PackageReports.add(%{
          "releases" => [release],
          "user" => author,
          "package" => package,
          "description" => description
        }).id

      PackageReports.accept(id)
      report = PackageReports.get(id)

      comment =
        PackageReports.new_comment(
          report,
          other_user,
          %{"text" => "We need to solve this."}
        )

      assert_delivered_email(
        Hexpm.Emails.report_commented(
          moderator,
          comment.author.username,
          report.id,
          comment.inserted_at
        )
      )
    end
  end

  test "mark_release/1", %{package: package, release: release} do
    PackageReports.mark_release(release)

    new_package =
      Packages.get(package.repository, package.name)
      |> Packages.preload()

    assert release.version in for(r <- new_package.releases, r.retirement != nil, do: r.version)
  end
end
