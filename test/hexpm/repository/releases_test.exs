defmodule Hexpm.Repository.ReleasesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Repository
  alias Hexpm.Repository.{Packages, Releases}

  setup do
    repository = insert(:repository, public: false)
    package = %{insert(:package) | repository: Repository.hexpm()}
    release = insert(:release, package: package, version: "0.1.0")
    user = insert(:user)

    %{
      repository: repository,
      package: package,
      release: release,
      user: user
    }
  end

  describe "publish/7" do
    test "publish private package with public dependency", %{
      repository: repository,
      package: package,
      user: user
    } do
      meta = %{
        default_meta(Fake.sequence(:package), "0.1.0")
        | "requirements" => [default_requirement(package.name, "~> 0.1.0")]
      }

      audit = audit_data(user)

      assert {:ok, _} =
               Releases.publish(
                 repository,
                 nil,
                 user,
                 "BODY",
                 meta,
                 "00",
                 audit: audit
               )
    end

    test "sets release.publisher to user when publish a new release" do
      repository = insert(:repository)
      user = insert(:user)
      meta = default_meta(Fake.sequence(:package), "0.1.0")
      audit = audit_data(user)

      {:ok, %{release: release}} =
        Releases.publish(repository, nil, user, "BODY", meta, "00", audit: audit)

      assert release.publisher_id == user.id
    end

    test "cant publish reserved package name", %{user: user} do
      Repo.insert_all("reserved_packages", [
        %{"repository_id" => 1, "name" => "reserved_name"}
      ])

      meta = default_meta("reserved_name", "0.1.0")
      audit = audit_data(user)

      assert {:error, :package, changeset, _} =
               Releases.publish(
                 Repository.hexpm(),
                 nil,
                 user,
                 "BODY",
                 meta,
                 "CHECKSUM",
                 audit: audit
               )

      assert %{name: "is reserved"} = errors_on(changeset)
    end

    test "cant publish reserved package version", %{package: package, user: user} do
      Repo.insert_all("reserved_packages", [
        %{"repository_id" => 1, "name" => package.name, "version" => "0.2.0"}
      ])

      meta = default_meta(package.name, "0.2.0")
      audit = audit_data(user)

      assert {:error, :release, changeset, _} =
               Releases.publish(
                 Repository.hexpm(),
                 package,
                 user,
                 "BODY",
                 meta,
                 "CHECKSUM",
                 audit: audit
               )

      assert %{version: "is reserved"} = errors_on(changeset)
    end

    test "cant publish using non-semantic version", %{package: package, user: user} do
      Repo.insert_all("reserved_packages", [
        %{"repository_id" => 1, "name" => package.name, "version" => "0.2.0"}
      ])

      meta = default_meta(package.name, "0.2")
      audit = audit_data(user)

      assert {:error, :version, changeset, _} =
               Releases.publish(
                 Repository.hexpm(),
                 package,
                 user,
                 "BODY",
                 meta,
                 "CHECKSUM",
                 audit: audit
               )

      assert %{version: "is invalid SemVer"} = errors_on(changeset)
    end
  end

  describe "revert/3" do
    test "revert release and package", %{
      package: package,
      release: release,
      user: user
    } do
      audit = audit_data(user)

      assert Releases.revert(package, release, audit: audit) == :ok
      refute Releases.get(package, "0.1.0")
      refute Packages.get(Repository.hexpm(), package.name)
    end

    test "revert only release", %{
      package: package,
      user: user
    } do
      audit = audit_data(user)
      release = insert(:release, package: package, version: "0.2.0")

      assert Releases.revert(package, release, audit: audit) == :ok
      refute Releases.get(package, "0.2.0")
      assert Packages.get(Repository.hexpm(), package.name)
    end
  end
end
