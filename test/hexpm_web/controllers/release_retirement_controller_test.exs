defmodule HexpmWeb.ReleaseRetirementControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{ReleaseRetirement, Releases}

  setup do
    maintainer = insert(:user_with_tfa)
    full_owner = insert(:user_with_tfa)

    package =
      insert(:package,
        package_owners: [
          build(:package_owner, user: full_owner, level: "full"),
          build(:package_owner, user: maintainer, level: "maintainer")
        ]
      )

    insert(:release, package: package, version: "1.0.0")

    insert(:release,
      package: package,
      version: "2.0.0",
      retirement: %ReleaseRetirement{reason: "security", message: "See CVE-2026-0001"}
    )

    %{maintainer: maintainer, full_owner: full_owner, package: package}
  end

  defp private_package do
    organization = insert(:organization)
    repository = insert(:repository, organization: organization, name: organization.name)
    package = insert(:package, repository_id: repository.id)
    insert(:release, package: package, version: "1.0.0")
    %{organization: organization, repository: repository, package: package}
  end

  defp owning_organization(package) do
    organization = insert(:organization)
    insert(:repository, organization: organization, name: organization.name)
    insert(:package_owner, package: package, user: organization.user, level: "full")
    organization
  end

  defp retirement(package, version), do: Releases.get(package, version).retirement

  defp audit_logs(action), do: Repo.all(from(a in AuditLog, where: a.action == ^action))

  defp retire_params(reason, message),
    do: %{"retirement" => %{"reason" => reason, "message" => message}}

  defp query(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.to_list()
  end

  describe "GET /packages/:name/:version/retire" do
    test "shows a maintainer the retire form", %{maintainer: maintainer, package: package} do
      html =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/1.0.0/retire")
        |> html_response(200)

      assert html =~ "Retire #{package.name} 1.0.0"

      assert [_form] =
               query(html, ~s(#retire-form[action="/packages/#{package.name}/1.0.0/retire"]))

      assert [] = query(html, "#unretire-form")

      options =
        html
        |> query("#retirement_reason option")
        |> Enum.map(&(&1 |> LazyHTML.attribute("value") |> List.first()))

      assert options == ["", "other", "invalid", "security", "deprecated", "renamed"]
    end

    test "fills in the retirement of a retired version and offers to unretire it", %{
      maintainer: maintainer,
      package: package
    } do
      html =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/2.0.0/retire")
        |> html_response(200)

      assert html =~ "Change the retirement of #{package.name} 2.0.0"

      assert [_selected] = query(html, ~s(#retirement_reason option[value="security"][selected]))
      assert [_message] = query(html, ~s(#retirement_message[value="See CVE-2026-0001"]))
      assert [_form] = query(html, "#unretire-form")
    end

    test "asks a maintainer without 2FA to enable it", %{package: package} do
      user = insert(:user)
      insert(:package_owner, package: package, user: user, level: "maintainer")

      html =
        build_conn()
        |> test_login(user)
        |> get("/packages/#{package.name}/2.0.0/retire")
        |> html_response(200)

      assert html =~ "Two-factor authentication is required to retire and unretire versions."
      assert [] = query(html, "#retire-form")
      assert [] = query(html, "#unretire-form")
    end

    test "is forbidden for a user who doesn't own the package", %{package: package} do
      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> get("/packages/#{package.name}/1.0.0/retire")

      assert conn.status == 403
    end

    test "is forbidden for a read-only member of an organization that owns the package", %{
      package: package
    } do
      organization = owning_organization(package)
      member = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: member, role: "read")

      conn =
        build_conn()
        |> test_login(member)
        |> get("/packages/#{package.name}/1.0.0/retire")

      assert conn.status == 403
    end

    test "shows a write member of an organization that owns the package the form", %{
      package: package
    } do
      organization = owning_organization(package)
      member = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: member, role: "write")

      html =
        build_conn()
        |> test_login(member)
        |> get("/packages/#{package.name}/1.0.0/retire")
        |> html_response(200)

      assert [_form] = query(html, "#retire-form")
    end

    test "redirects to login when logged out", %{package: package} do
      conn = get(build_conn(), "/packages/#{package.name}/1.0.0/retire")
      assert redirected_to(conn) =~ "/login"
    end

    test "redirects to sudo without sudo mode", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: false)
        |> get("/packages/#{package.name}/1.0.0/retire")

      assert redirected_to(conn) == "/sudo"
    end

    test "is not found for a version that doesn't exist", %{
      maintainer: maintainer,
      package: package
    } do
      conn = test_login(build_conn(), maintainer)

      assert conn |> get("/packages/#{package.name}/3.0.0/retire") |> response(404)
      assert conn |> get("/packages/#{package.name}/not-a-version/retire") |> response(404)
    end

    test "is not found for a private package the user can't reach" do
      %{repository: repository, package: package} = private_package()

      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> get("/packages/#{repository.name}/#{package.name}/1.0.0/retire")

      assert conn.status == 404
    end

    test "is forbidden for a read-only member of a private package's organization" do
      %{organization: organization, repository: repository, package: package} =
        private_package()

      member = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: member, role: "read")

      conn =
        build_conn()
        |> test_login(member)
        |> get("/packages/#{repository.name}/#{package.name}/1.0.0/retire")

      assert conn.status == 403
    end
  end

  describe "POST /packages/:name/:version/retire" do
    test "retires the version", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> post(
          "/packages/#{package.name}/1.0.0/retire",
          retire_params("deprecated", "Use new_package instead")
        )

      assert redirected_to(conn) == "/packages/#{package.name}/versions"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "#{package.name} 1.0.0 has been retired."

      assert %ReleaseRetirement{reason: "deprecated", message: "Use new_package instead"} =
               retirement(package, "1.0.0")

      assert [%AuditLog{user_id: user_id, params: params}] = audit_logs("release.retire")
      assert user_id == maintainer.id
      assert params["release"]["version"] == "1.0.0"
    end

    test "changes the retirement of a retired version", %{
      maintainer: maintainer,
      package: package
    } do
      build_conn()
      |> test_login(maintainer)
      |> post(
        "/packages/#{package.name}/2.0.0/retire",
        retire_params("invalid", "Does not compile")
      )
      |> response(302)

      assert %ReleaseRetirement{reason: "invalid", message: "Does not compile"} =
               retirement(package, "2.0.0")
    end

    test "retires a private package's version for a write member of its organization" do
      %{organization: organization, repository: repository, package: package} =
        private_package()

      member = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: member, role: "write")

      conn =
        build_conn()
        |> test_login(member)
        |> post(
          "/packages/#{repository.name}/#{package.name}/1.0.0/retire",
          retire_params("security", "See CVE-2026-0002")
        )

      assert redirected_to(conn) == "/packages/#{repository.name}/#{package.name}/versions"
      assert retirement(package, "1.0.0").reason == "security"
    end

    test "shows the errors of an invalid retirement", %{maintainer: maintainer, package: package} do
      conn = test_login(build_conn(), maintainer)

      html =
        conn
        |> post("/packages/#{package.name}/1.0.0/retire", retire_params("", ""))
        |> html_response(400)

      assert html =~ "can&#39;t be blank"

      html =
        conn
        |> post(
          "/packages/#{package.name}/1.0.0/retire",
          retire_params("security", String.duplicate("a", 141))
        )
        |> html_response(400)

      assert html =~ "should be at most 140 character(s)"

      html =
        conn
        |> post("/packages/#{package.name}/1.0.0/retire", retire_params("unknown", "Message"))
        |> html_response(400)

      assert html =~ "is invalid"

      refute retirement(package, "1.0.0")
      assert audit_logs("release.retire") == []
    end

    test "shows the errors of a retirement that isn't a map", %{
      maintainer: maintainer,
      package: package
    } do
      html =
        build_conn()
        |> test_login(maintainer)
        |> post("/packages/#{package.name}/1.0.0/retire", %{"retirement" => "security"})
        |> html_response(400)

      assert html =~ "can&#39;t be blank"
      refute retirement(package, "1.0.0")
    end

    test "requires a message", %{maintainer: maintainer, package: package} do
      html =
        build_conn()
        |> test_login(maintainer)
        |> post("/packages/#{package.name}/1.0.0/retire", retire_params("security", " "))
        |> html_response(400)

      assert html =~ "can&#39;t be blank"
      refute retirement(package, "1.0.0")
    end

    test "is forbidden without 2FA", %{package: package} do
      user = insert(:user)
      insert(:package_owner, package: package, user: user, level: "maintainer")

      conn =
        build_conn()
        |> test_login(user)
        |> post("/packages/#{package.name}/1.0.0/retire", retire_params("security", "Message"))

      assert conn.status == 403
      refute retirement(package, "1.0.0")
    end

    test "is forbidden for a user who doesn't own the package", %{package: package} do
      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> post("/packages/#{package.name}/1.0.0/retire", retire_params("security", "Message"))

      assert conn.status == 403
      refute retirement(package, "1.0.0")
    end

    test "redirects to sudo without sudo mode", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: false)
        |> post("/packages/#{package.name}/1.0.0/retire", retire_params("security", "Message"))

      assert redirected_to(conn) == "/sudo"
      refute retirement(package, "1.0.0")
    end
  end

  describe "DELETE /packages/:name/:version/retire" do
    test "unretires the version", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> delete("/packages/#{package.name}/2.0.0/retire")

      assert redirected_to(conn) == "/packages/#{package.name}/versions"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "#{package.name} 2.0.0 is no longer retired."

      refute retirement(package, "2.0.0")
      assert [%AuditLog{user_id: user_id}] = audit_logs("release.unretire")
      assert user_id == full_owner.id
    end

    test "leaves a version that isn't retired alone", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> delete("/packages/#{package.name}/1.0.0/retire")

      assert redirected_to(conn) == "/packages/#{package.name}/versions"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "#{package.name} 1.0.0 is not retired."

      assert audit_logs("release.unretire") == []
    end

    test "is forbidden without 2FA", %{package: package} do
      user = insert(:user)
      insert(:package_owner, package: package, user: user, level: "maintainer")

      conn =
        build_conn()
        |> test_login(user)
        |> delete("/packages/#{package.name}/2.0.0/retire")

      assert conn.status == 403
      assert retirement(package, "2.0.0")
    end

    test "is forbidden for a user who doesn't own the package", %{package: package} do
      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> delete("/packages/#{package.name}/2.0.0/retire")

      assert conn.status == 403
      assert retirement(package, "2.0.0")
    end
  end

  describe "GET /packages/:name/versions/retire" do
    test "shows a maintainer the form and what it retires", %{
      maintainer: maintainer,
      package: package
    } do
      html =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/versions/retire")
        |> html_response(200)

      assert html =~ "Retire all versions of #{package.name}"

      assert [_form] =
               query(
                 html,
                 ~s(#retire-all-form[action="/packages/#{package.name}/versions/retire"])
               )

      assert [counts] = query(html, "#retire-all-counts")

      assert counts |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim() ==
               "This retires the 1 version not retired yet. " <>
                 "Versions that are already retired keep their reason and message unless you replace them."

      assert [_checkbox] =
               query(html, ~s{input#retire_all_replace[name="replace"]:not([checked])})
    end

    test "leaves out the replace option when no version is retired", %{maintainer: maintainer} do
      package = insert(:package)
      insert(:package_owner, package: package, user: maintainer, level: "maintainer")
      insert(:release, package: package, version: "1.0.0")
      insert(:release, package: package, version: "1.1.0")

      html =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/versions/retire")
        |> html_response(200)

      assert html =~ "This retires 2 versions."
      assert [] = query(html, "#retire_all_replace")
    end

    test "asks a maintainer without 2FA to enable it", %{package: package} do
      user = insert(:user)
      insert(:package_owner, package: package, user: user, level: "maintainer")

      html =
        build_conn()
        |> test_login(user)
        |> get("/packages/#{package.name}/versions/retire")
        |> html_response(200)

      assert html =~ "Two-factor authentication is required to retire and unretire versions."
      assert [] = query(html, "#retire-all-form")
    end

    test "is forbidden for a user who doesn't own the package", %{package: package} do
      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> get("/packages/#{package.name}/versions/retire")

      assert conn.status == 403
    end

    test "redirects to login when logged out", %{package: package} do
      conn = get(build_conn(), "/packages/#{package.name}/versions/retire")
      assert redirected_to(conn) =~ "/login"
    end

    test "is not found for a private package the user can't reach" do
      %{repository: repository, package: package} = private_package()

      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> get("/packages/#{repository.name}/#{package.name}/versions/retire")

      assert conn.status == 404
    end
  end

  describe "POST /packages/:name/versions/retire" do
    test "retires the versions that aren't retired", %{maintainer: maintainer, package: package} do
      insert(:release, package: package, version: "3.0.0")

      conn =
        build_conn()
        |> test_login(maintainer)
        |> post(
          "/packages/#{package.name}/versions/retire",
          retire_params("deprecated", "Use new_package instead")
        )

      assert redirected_to(conn) == "/packages/#{package.name}/versions"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Retired 2 versions of #{package.name}."

      for version <- ["1.0.0", "3.0.0"] do
        assert %ReleaseRetirement{reason: "deprecated", message: "Use new_package instead"} =
                 retirement(package, version)
      end

      assert %ReleaseRetirement{reason: "security", message: "See CVE-2026-0001"} =
               retirement(package, "2.0.0")

      versions =
        "release.retire"
        |> audit_logs()
        |> Enum.map(fn log ->
          assert log.user_id == maintainer.id
          log.params["release"]["version"]
        end)

      assert Enum.sort(versions) == ["1.0.0", "3.0.0"]
    end

    test "replaces existing retirements when asked", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> post(
          "/packages/#{package.name}/versions/retire",
          Map.put(retire_params("renamed", "Use new_package instead"), "replace", "true")
        )

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Retired 2 versions of #{package.name}."

      for version <- ["1.0.0", "2.0.0"] do
        assert %ReleaseRetirement{reason: "renamed", message: "Use new_package instead"} =
                 retirement(package, version)
      end
    end

    test "says so when every version is already retired", %{
      maintainer: maintainer,
      package: package
    } do
      build_conn()
      |> test_login(maintainer)
      |> post("/packages/#{package.name}/versions/retire", retire_params("security", "Message"))

      conn =
        build_conn()
        |> test_login(maintainer)
        |> post("/packages/#{package.name}/versions/retire", retire_params("invalid", "Other"))

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "All versions of #{package.name} are already retired."

      assert retirement(package, "1.0.0").reason == "security"
    end

    test "retires a private package's versions for a write member of its organization" do
      %{organization: organization, repository: repository, package: package} =
        private_package()

      member = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: member, role: "write")

      conn =
        build_conn()
        |> test_login(member)
        |> post(
          "/packages/#{repository.name}/#{package.name}/versions/retire",
          retire_params("security", "See CVE-2026-0002")
        )

      assert redirected_to(conn) == "/packages/#{repository.name}/#{package.name}/versions"
      assert retirement(package, "1.0.0").reason == "security"
    end

    test "shows the errors of an invalid retirement and keeps the replace choice", %{
      maintainer: maintainer,
      package: package
    } do
      html =
        build_conn()
        |> test_login(maintainer)
        |> post(
          "/packages/#{package.name}/versions/retire",
          Map.put(retire_params("security", ""), "replace", "true")
        )
        |> html_response(400)

      assert html =~ "can&#39;t be blank"
      assert [_checkbox] = query(html, "input#retire_all_replace[checked]")
      refute retirement(package, "1.0.0")
      assert retirement(package, "2.0.0").message == "See CVE-2026-0001"
    end

    test "is forbidden without 2FA", %{package: package} do
      user = insert(:user)
      insert(:package_owner, package: package, user: user, level: "maintainer")

      conn =
        build_conn()
        |> test_login(user)
        |> post("/packages/#{package.name}/versions/retire", retire_params("security", "Message"))

      assert conn.status == 403
      refute retirement(package, "1.0.0")
    end

    test "is forbidden for a user who doesn't own the package", %{package: package} do
      conn =
        build_conn()
        |> test_login(insert(:user_with_tfa))
        |> post("/packages/#{package.name}/versions/retire", retire_params("security", "Message"))

      assert conn.status == 403
      refute retirement(package, "1.0.0")
    end

    test "redirects to sudo without sudo mode", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: false)
        |> post("/packages/#{package.name}/versions/retire", retire_params("security", "Message"))

      assert redirected_to(conn) == "/sudo"
      refute retirement(package, "1.0.0")
    end
  end

  describe "GET /packages/:name/versions" do
    test "links each version to its retirement page for a maintainer", %{
      maintainer: maintainer,
      package: package
    } do
      html =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/versions")
        |> html_response(200)

      links =
        html
        |> query("table a[href$='/retire']")
        |> Enum.map(fn link ->
          {link |> LazyHTML.attribute("href") |> List.first(),
           link |> LazyHTML.attribute("title") |> List.first()}
        end)

      assert links == [
               {"/packages/#{package.name}/2.0.0/retire", "Manage retirement"},
               {"/packages/#{package.name}/1.0.0/retire", "Retire version"}
             ]

      assert [_link] =
               query(
                 html,
                 ~s(a#retire-all-versions[href="/packages/#{package.name}/versions/retire"])
               )
    end

    test "has no retirement links for anyone else", %{package: package} do
      for conn <- [build_conn(), test_login(build_conn(), insert(:user))] do
        html = conn |> get("/packages/#{package.name}/versions") |> html_response(200)
        assert [] = query(html, "a[href$='/retire']")
      end
    end
  end
end
