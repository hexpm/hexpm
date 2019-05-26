defmodule HexpmWeb.API.ReleaseControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{Package, RegistryBuilder, Release, Repository}

  setup do
    user = insert(:user)
    repository = insert(:repository)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])
    release = insert(:release, package: package, version: "0.0.1", has_docs: true)

    %{
      user: user,
      repository: repository,
      organization: repository.organization,
      package: package,
      release: release
    }
  end

  describe "POST /api/packages/:name/releases" do
    test "create release and new package", %{user: user} do
      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/packages/#{meta.name}/releases", create_tar(meta, []))

      result = json_response(conn, 201)
      assert result["url"] =~ "api/packages/#{meta.name}/releases/1.0.0"
      assert result["html_url"] =~ "packages/#{meta.name}/1.0.0"
      assert result["publisher"]["username"] == user.username

      package = Hexpm.Repo.get_by!(Package, name: meta.name)
      package_owner = Hexpm.Repo.one!(assoc(package, :owners))
      assert package_owner.id == user.id

      log = Hexpm.Repo.one!(AuditLog)
      assert log.user_id == user.id
      assert log.organization_id == nil
      assert log.action == "release.publish"
      assert log.params["package"]["name"] == meta.name
      assert log.params["release"]["version"] == "1.0.0"
    end

    test "update package", %{user: user, package: package} do
      meta = %{name: package.name, version: "1.0.0", description: "awesomeness"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/packages/#{package.name}/releases", create_tar(meta, []))

      assert conn.status == 201
      result = json_response(conn, 201)
      assert result["url"] =~ "/api/packages/#{package.name}/releases/1.0.0"
      assert result["html_url"] =~ "packages/#{package.name}/1.0.0"

      assert Hexpm.Repo.get_by(Package, name: package.name).meta.description == "awesomeness"
    end

    test "update package fails when version is invalid", %{user: user, package: package} do
      meta = %{name: package.name, version: "1.0-dev", description: "not-so-awesome"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/packages/#{package.name}/releases", create_tar(meta, []))

      assert conn.status == 422
      result = json_response(conn, 422)
      assert result["message"] =~ "Validation error"
      assert result["errors"] == %{"version" => "is invalid SemVer"}
    end

    test "create release checks if package name is correct", %{user: user, package: package} do
      meta = %{name: Fake.sequence(:package), version: "0.1.0", description: "description"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/packages/#{package.name}/releases", create_tar(meta, []))

      result = json_response(conn, 422)
      assert result["errors"]["name"] == "metadata does not match package name"

      meta = %{name: package.name, version: "1.0.0", description: "description"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/packages/#{Fake.sequence(:package)}/releases", create_tar(meta, []))

      # Bad error message but /api/publish solves it
      # https://github.com/hexpm/hexpm/issues/489
      result = json_response(conn, 422)
      assert result["errors"]["name"] == "has already been taken"
    end
  end

  describe "POST /api/publish" do
    test "create release and new package", %{user: user} do
      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 201)
      assert result["url"] =~ "api/packages/#{meta.name}/releases/1.0.0"
      assert result["html_url"] =~ "packages/#{meta.name}/1.0.0"

      package = Hexpm.Repo.get_by!(Package, name: meta.name)
      package_owner = Hexpm.Repo.one!(assoc(package, :owners))
      assert package_owner.id == user.id

      log = Hexpm.Repo.one!(AuditLog)
      assert log.user_id == user.id
      assert log.organization_id == nil
      assert log.action == "release.publish"
      assert log.params["package"]["name"] == meta.name
      assert log.params["release"]["version"] == "1.0.0"
    end

    test "update package", %{user: user, package: package} do
      meta = %{name: package.name, version: "1.0.0", description: "awesomeness"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      assert conn.status == 201
      result = json_response(conn, 201)
      assert result["url"] =~ "/api/packages/#{package.name}/releases/1.0.0"
      assert result["html_url"] =~ "packages/#{package.name}/1.0.0"

      assert Hexpm.Repo.get_by(Package, name: package.name).meta.description == "awesomeness"
    end

    test "create release authorizes existing package", %{package: package} do
      other_user = insert(:user)
      meta = %{name: package.name, version: "0.1.0", description: "description"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(other_user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(403)
    end

    test "create release authorizes" do
      meta = %{name: Fake.sequence(:package), version: "0.1.0", description: "description"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "WRONG")
        |> post("api/publish", create_tar(meta, []))

      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
    end

    test "update package authorizes", %{package: package} do
      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "WRONG")
        |> post("api/publish", create_tar(meta, []))

      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
    end

    test "organization owned package", %{user: user, organization: organization} do
      package =
        insert(
          :package,
          package_owners: [build(:package_owner, user: organization.user)]
        )

      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      insert(:organization_user, organization: organization, user: user, role: "write")

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(201)
    end

    test "organization owned package authorizes", %{user: user, organization: organization} do
      package =
        insert(
          :package,
          package_owners: [build(:package_owner, user: organization.user)]
        )

      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(403)
    end

    test "organization owned package requries write permission", %{
      user: user,
      organization: organization
    } do
      package =
        insert(
          :package,
          package_owners: [build(:package_owner, user: organization.user)]
        )

      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      insert(:organization_user, organization: organization, user: user, role: "read")

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(403)
    end

    # test "organization needs to have active billing", %{user: user} do
    #   organization = insert(:organization, billing_active: false)
    #   insert(:organization_user, organization: organization, user: user, role: "write")
    #
    #   package =
    #     insert(
    #       :package,
    #       package_owners: [build(:package_owner, user: organization.user)]
    #     )
    #
    #   meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}
    #
    #   build_conn()
    #   |> put_req_header("content-type", "application/octet-stream")
    #   |> put_req_header("authorization", key_for(user))
    #   |> post("api/publish", create_tar(meta, []))
    #   |> json_response(403)
    # end

    test "create package validates", %{user: user, package: package} do
      meta = %{name: package.name, version: "1.0.0", links: "invalid", description: "description"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 422)
      assert result["errors"]["meta"]["links"] == "expected type map(string)"
    end

    test "create package casts proplist metadata", %{user: user, package: package} do
      meta = %{
        name: package.name,
        version: "1.0.0",
        links: %{"link" => "http://localhost"},
        extra: %{"key" => "value"},
        description: "description"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      json_response(conn, 201)
      package = Hexpm.Repo.get_by!(Package, name: package.name)
      assert package.meta.links == %{"link" => "http://localhost"}
      assert package.meta.extra == %{"key" => "value"}
    end

    test "create releases", %{user: user} do
      meta = %{
        name: Fake.sequence(:package),
        app: "other",
        version: "0.0.1",
        description: "description"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/packages/#{meta.name}/releases", create_tar(meta, []))

      result = json_response(conn, 201)
      assert result["meta"]["app"] == "other"
      assert result["url"] =~ "/api/packages/#{meta.name}/releases/0.0.1"
      assert result["html_url"] =~ "packages/#{meta.name}/0.0.1"

      meta = %{name: meta.name, version: "0.0.2", description: "description"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(201)

      package = Hexpm.Repo.get_by!(Package, name: meta.name)
      package_id = package.id

      assert [
               %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 2}},
               %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}}
             ] = Release.all(package) |> Hexpm.Repo.all() |> Release.sort()

      Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1")
    end

    test "create release also creates package", %{user: user} do
      meta = %{name: Fake.sequence(:package), version: "1.0.0", description: "Web framework"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(201)

      Hexpm.Repo.get_by!(Package, name: meta.name)
    end

    test "update release", %{user: user} do
      meta = %{name: Fake.sequence(:package), version: "0.0.1", description: "description"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/packages/#{meta.name}/releases", create_tar(meta, []))
      |> json_response(201)

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(200)

      package = Hexpm.Repo.get_by!(Package, name: meta.name)
      Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1")

      assert [%AuditLog{action: "release.publish"}, %AuditLog{action: "release.publish"}] =
               Hexpm.Repo.all(AuditLog)
    end

    test "update release with different and unresolved requirements", %{
      user: user,
      package: package
    } do
      name = Fake.sequence(:package)
      reqs = [%{name: package.name, requirement: "~> 0.0.1", app: "app", optional: false}]
      meta = %{name: name, version: "0.0.1", requirements: reqs, description: "description"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 201)

      assert result["requirements"] == %{
               package.name => %{"app" => "app", "optional" => false, "requirement" => "~> 0.0.1"}
             }

      # Disabled because of resolver bug
      # re-publish with unresolved requirement
      # reqs = [%{name: package.name, requirement: "~> 9.0", app: "app", optional: false}]
      # meta = %{name: name, version: "0.0.1", requirements: reqs, description: "description"}

      # conn =
      #   build_conn()
      #   |> put_req_header("content-type", "application/octet-stream")
      #   |> put_req_header("authorization", key_for(user))
      #   |> post("api/packages/#{meta.name}/releases", create_tar(meta, []))
      #
      # result = json_response(conn, 422)
      # assert result["errors"]["requirements"] =~ ~s(Failed to use "#{package.name}")
    end

    test "can update release within package one hour grace period", %{
      user: user,
      package: package,
      release: release
    } do
      datetime =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-36000, :second)
        |> DateTime.from_naive!("Etc/UTC")

      Ecto.Changeset.change(package, inserted_at: datetime)
      |> Hexpm.Repo.update!()

      Ecto.Changeset.change(release, inserted_at: datetime)
      |> Hexpm.Repo.update!()

      meta = %{name: package.name, version: "0.0.1", description: "description"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(200)
    end

    test "cannot update release after grace period", %{
      user: user,
      package: package,
      release: release
    } do
      Ecto.Changeset.change(package, inserted_at: %{DateTime.utc_now() | year: 2000})
      |> Hexpm.Repo.update!()

      Ecto.Changeset.change(release, inserted_at: %{DateTime.utc_now() | year: 2000})
      |> Hexpm.Repo.update!()

      meta = %{name: package.name, version: "0.0.1", description: "description"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 422)

      assert result["errors"]["inserted_at"] ==
               "can only modify a release up to one hour after creation"
    end

    test "create releases with requirements", %{user: user, package: package} do
      reqs = [%{name: package.name, requirement: "~> 0.0.1", app: "app", optional: false}]

      meta = %{
        name: Fake.sequence(:package),
        version: "0.0.1",
        requirements: reqs,
        description: "description"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 201)

      assert result["requirements"] == %{
               package.name => %{"app" => "app", "optional" => false, "requirement" => "~> 0.0.1"}
             }

      release =
        Hexpm.Repo.get_by!(Package, name: meta.name)
        |> assoc(:releases)
        |> Hexpm.Repo.get_by!(version: "0.0.1")
        |> Hexpm.Repo.preload(:requirements)

      assert [%{app: "app", requirement: "~> 0.0.1", optional: false}] = release.requirements
    end

    test "create releases with requirements validates requirement", %{
      user: user,
      package: package
    } do
      reqs = [%{name: package.name, requirement: "~> invalid", app: "app", optional: false}]

      meta = %{
        name: Fake.sequence(:package),
        version: "0.0.1",
        requirements: reqs,
        description: "description"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 422)

      assert result["errors"]["requirements"][package.name] ==
               ~s(invalid requirement: "~> invalid")
    end

    test "create releases with requirements validates package name", %{user: user} do
      reqs = [%{name: "nonexistant_package", requirement: "~> 1.0", app: "app", optional: false}]

      meta = %{
        name: Fake.sequence(:package),
        version: "0.0.1",
        requirements: reqs,
        description: "description"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/publish", create_tar(meta, []))

      result = json_response(conn, 422)

      assert result["errors"]["requirements"]["nonexistant_package"] ==
               "package does not exist in repository \"hexpm\""
    end

    # Disabled because of resolver bug
    # test "create releases with requirements validates resolution", %{user: user, package: package} do
    #   reqs = [%{name: package.name, requirement: "~> 1.0", app: "app", optional: false}]
    #
    #   meta = %{
    #     name: Fake.sequence(:package),
    #     version: "0.1.0",
    #     requirements: reqs,
    #     description: "description"
    #   }
    #
    #   conn =
    #     build_conn()
    #     |> put_req_header("content-type", "application/octet-stream")
    #     |> put_req_header("authorization", key_for(user))
    #     |> post("api/publish", create_tar(meta, []))
    #
    #   result = json_response(conn, 422)
    #
    #   assert result["errors"]["requirements"] =~ ~s(Failed to use "#{package.name}" because)
    # end

    test "create release updates registry", %{user: user, package: package} do
      RegistryBuilder.full_build(Repository.hexpm())
      registry_before = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", [])

      reqs = [%{name: package.name, app: "app", requirement: "~> 0.0.1", optional: false}]

      meta = %{
        name: Fake.sequence(:package),
        app: "app",
        version: "0.0.1",
        requirements: reqs,
        description: "description"
      }

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/publish", create_tar(meta, []))
      |> json_response(201)

      registry_after = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", [])
      assert registry_before != registry_after
    end
  end

  describe "POST /api/:repository/packages/:name/releases" do
    test "new package authorizes", %{user: user, repository: repository} do
      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/#{meta.name}/releases",
        create_tar(meta, [])
      )
      |> json_response(403)
    end

    test "existing package authorizes", %{user: user, repository: repository} do
      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/#{meta.name}/releases",
        create_tar(meta, [])
      )
      |> json_response(403)
    end
  end

  describe "POST /api/repos/:repository/publish" do
    test "new package authorizes", %{user: user, repository: repository} do
      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
      |> json_response(403)
    end

    test "existing package authorizes", %{user: user, repository: repository} do
      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
      |> json_response(403)
    end

    test "new package requries write permission", %{user: user, repository: repository} do
      insert(:organization_user, organization: repository.organization, user: user, role: "read")

      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
      |> json_response(403)

      refute Hexpm.Repo.get_by(Package, name: meta.name)
    end

    test "organization needs to have active billing", %{user: user} do
      repository = insert(:repository, organization: build(:organization, billing_active: false))
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
      |> json_response(403)

      refute Hexpm.Repo.get_by(Package, name: meta.name)
    end

    test "new package", %{user: user, repository: repository} do
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      meta = %{
        name: Fake.sequence(:package),
        version: "1.0.0",
        description: "Domain-specific language."
      }

      result =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
        |> json_response(201)

      assert result["url"] =~
               "api/repos/#{repository.name}/packages/#{meta.name}/releases/1.0.0"

      package = Hexpm.Repo.get_by!(Package, name: meta.name)
      assert package.repository_id == repository.id
    end

    test "existing package", %{user: user, repository: repository} do
      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:organization_user, organization: repository.organization, user: user)

      meta = %{name: package.name, version: "1.0.0", description: "Domain-specific language."}

      result =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(user))
        |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
        |> json_response(201)

      assert result["url"] =~
               "api/repos/#{repository.name}/packages/#{meta.name}/releases/1.0.0"

      package = Hexpm.Repo.get_by!(Package, name: meta.name)
      assert package.repository_id == repository.id
    end

    test "can update private package after grace period", %{
      user: user,
      repository: repository
    } do
      package =
        insert(
          :package,
          package_owners: [build(:package_owner, user: user)],
          repository_id: repository.id
        )

      insert(
        :release,
        package: package,
        version: "0.0.1",
        inserted_at: %{DateTime.utc_now() | year: 2000}
      )

      insert(:organization_user, organization: repository.organization, user: user)

      meta = %{name: package.name, version: "0.0.1", description: "description"}

      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("authorization", key_for(user))
      |> post("api/repos/#{repository.name}/publish", create_tar(meta, []))
      |> json_response(200)
    end
  end

  describe "DELETE /api/packages/:name/releases/:version" do
    test "delete release validates release age", %{user: user, package: package, release: release} do
      Ecto.Changeset.change(package, inserted_at: %{DateTime.utc_now() | year: 2000})
      |> Hexpm.Repo.update!()

      Ecto.Changeset.change(release, inserted_at: %{DateTime.utc_now() | year: 2000})
      |> Hexpm.Repo.update!()

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> delete("api/packages/#{package.name}/releases/0.0.1")

      result = json_response(conn, 422)

      assert result["errors"]["inserted_at"] ==
               "can only delete a release up to one hour after creation"
    end

    test "delete package validates dependants", %{user: user, package: package} do
      package2 = insert(:package)
      release2 = insert(:release, package: package2, version: "0.0.1")
      insert(:requirement, release: release2, dependency: package, requirement: "~> 0.0.1")

      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> delete("api/packages/#{package.name}/releases/0.0.1")
        |> json_response(422)

      assert result["errors"]["name"] ==
               "you cannot delete this package because other packages depend on it"
    end

    test "delete release", %{user: user, package: package, release: release} do
      Ecto.Changeset.change(release, inserted_at: %{DateTime.utc_now() | year: 2030})
      |> Hexpm.Repo.update!()

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/packages/#{package.name}/releases/0.0.1")
      |> response(204)

      refute Hexpm.Repo.get_by(Package, name: package.name)
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1")

      [log] = Hexpm.Repo.all(AuditLog)
      assert log.user_id == user.id
      assert log.action == "release.revert"
      assert log.params["package"]["name"] == package.name
      assert log.params["release"]["version"] == "0.0.1"
    end
  end

  describe "DELETE /api/repos/:repository/packages/:name/releases/:version" do
    test "authorizes", %{user: user, repository: repository} do
      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1")
      |> response(403)

      assert Hexpm.Repo.get_by(Package, name: package.name)
      assert Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1")
    end

    test "organization needs to have active billing", %{user: user} do
      repository = insert(:repository, organization: build(:organization, billing_active: false))
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1")
      |> response(403)

      assert Hexpm.Repo.get_by(Package, name: package.name)
      assert Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1")
    end

    test "delete release", %{user: user, repository: repository} do
      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: repository.organization, user: user)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1")
      |> response(204)

      refute Hexpm.Repo.get_by(Package, name: package.name)
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1")
    end

    test "can delete private package release after grace period", %{
      user: user,
      repository: repository
    } do
      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(
        :release,
        package: package,
        version: "0.0.1",
        inserted_at: %{DateTime.utc_now() | year: 2000}
      )

      insert(:organization_user, organization: repository.organization, user: user)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1")
      |> response(204)
    end
  end

  describe "GET /api/packages/:name/releases/:version" do
    test "get release", %{package: package, release: release} do
      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}")
        |> json_response(200)

      assert result["url"] ==
               "http://localhost:5000/api/packages/#{package.name}/releases/#{release.version}"

      assert result["html_url"] ==
               "http://localhost:5000/packages/#{package.name}/#{release.version}"

      assert result["docs_html_url"] ==
               "http://localhost:5002/#{package.name}/#{release.version}/"

      assert result["version"] == "#{release.version}"
    end

    test "get unknown release", %{package: package} do
      conn = get(build_conn(), "api/packages/#{package.name}/releases/1.2.3")
      assert conn.status == 404

      conn = get(build_conn(), "api/packages/unknown/releases/1.2.3")
      assert conn.status == 404
    end

    test "get release with requirements", %{package: package, release: release} do
      package2 = insert(:package)
      insert(:release, package: package2, version: "0.0.1")
      insert(:requirement, release: release, dependency: package2, requirement: "~> 0.0.1")

      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}")
        |> json_response(200)

      assert result["url"] =~ "/api/packages/#{package.name}/releases/#{release.version}"
      assert result["html_url"] =~ "/packages/#{package.name}/#{release.version}"
      assert result["version"] == "#{release.version}"
      assert result["requirements"][package2.name]["requirement"] == "~> 0.0.1"
    end
  end

  describe "GET /api/repos/:repository/packages/:name/releases/:version" do
    test "get release authorizes", %{user: user, repository: repository} do
      package = insert(:package, repository_id: repository.id)
      insert(:release, package: package, version: "0.0.1")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1")
      |> json_response(403)
    end

    test "get release returns 403 for non-existant repository", %{user: user} do
      package = insert(:package)
      insert(:release, package: package, version: "0.0.1")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/NONEXISTANT_REPOSITORY/packages/#{package.name}/releases/0.0.1")
      |> json_response(403)
    end

    test "get release", %{user: user, repository: repository} do
      package = insert(:package, repository_id: repository.id)
      insert(:release, package: package, version: "0.0.1", has_docs: true)
      insert(:organization_user, organization: repository.organization, user: user)

      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1")
        |> json_response(200)

      assert result["url"] ==
               "http://localhost:5000/api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1"

      assert result["html_url"] ==
               "http://localhost:5000/packages/#{repository.name}/#{package.name}/0.0.1"

      assert result["docs_html_url"] ==
               "http://#{repository.name}.localhost:5002/#{package.name}/0.0.1/"

      assert result["version"] == "0.0.1"
    end
  end

  describe "GET /api/packages/:name/releases/:version/downloads" do
    setup do
      user = insert(:user)
      repository = insert(:repository)
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      relprev = insert(:release, package: package, version: "0.0.1")
      release = insert(:release, package: package, version: "0.0.2")

      insert(:download, release: relprev, downloads: 8, day: ~D[2000-01-01])
      insert(:download, release: release, downloads: 1, day: ~D[2000-01-01])
      insert(:download, release: release, downloads: 3, day: ~D[2000-02-01])
      insert(:download, release: release, downloads: 2, day: ~D[2000-02-07])
      insert(:download, release: release, downloads: 4, day: ~D[2000-02-08])

      Hexpm.Repo.refresh_view(Hexpm.Repository.ReleaseDownload)

      %{
        user: user,
        repository: repository,
        package: package,
        release: release
      }
    end

    test "get release downloads (all by default)", %{package: package, release: release} do
      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}")
        |> json_response(200)

      assert result["version"] == "#{release.version}"
      assert result["downloads"] == 10

      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}?downloads=all")
        |> json_response(200)

      assert result["version"] == "#{release.version}"
      assert result["downloads"] == 10

      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}?downloads=xxx")
        |> json_response(200)

      assert result["version"] == "#{release.version}"
      assert result["downloads"] == 10
    end

    test "get release downloads by day", %{package: package, release: release} do
      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}?downloads=day")
        |> json_response(200)

      assert result["version"] == "#{release.version}"

      assert result["downloads"] == [
               ["2000-01-01", 1],
               ["2000-02-01", 3],
               ["2000-02-07", 2],
               ["2000-02-08", 4]
             ]
    end

    test "get release downloads by month", %{package: package, release: release} do
      result =
        build_conn()
        |> get("api/packages/#{package.name}/releases/#{release.version}?downloads=month")
        |> json_response(200)

      assert result["version"] == "#{release.version}"

      assert result["downloads"] == [
               ["2000-01", 1],
               ["2000-02", 9]
             ]
    end
  end
end
