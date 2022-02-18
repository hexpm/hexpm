defmodule Hexpm.Repository.ReleasesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Repository
  alias Hexpm.Repository.{Packages, Releases}

  setup do
    repository = insert(:repository)
    package = %{insert(:package) | repository: Repository.hexpm()}
    release = insert(:release, package: package, version: "0.1.0")
    user = insert(:user)
    hexpm = Hexpm.Repo.get(Repository, 1)

    %{
      repository: repository,
      package: package,
      release: release,
      user: user,
      hexpm: hexpm
    }
  end

  describe "publish/7" do
    test "publish package pushes artifacts", %{hexpm: hexpm, user: user} do
      name = Fake.sequence(:package)
      meta = default_meta(name, "0.1.0")
      audit = audit_data(user)

      Hexpm.Store.delete(:repo_bucket, "tarballs/#{name}-0.1.0.tar")
      Hexpm.Store.delete(:repo_bucket, "packages/#{name}")

      assert {:ok, _} =
               Releases.publish(
                 hexpm,
                 nil,
                 user,
                 "BODY",
                 meta,
                 "00",
                 "00",
                 audit: audit,
                 replace: false
               )

      assert Hexpm.Store.get(:repo_bucket, "tarballs/#{name}-0.1.0.tar", [])
      assert registry = Hexpm.Store.get(:repo_bucket, "packages/#{name}", [])
      assert Enum.any?(decode_registry_package(registry), &match?(%{version: "0.1.0"}, &1))
    end

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
                 "00",
                 audit: audit,
                 replace: false
               )
    end

    test "sets release.publisher to user when publish a new release" do
      repository = insert(:repository)
      user = insert(:user)
      meta = default_meta(Fake.sequence(:package), "0.1.0")
      audit = audit_data(user)

      {:ok, %{release: release}} =
        Releases.publish(repository, nil, user, "BODY", meta, "00", "00",
          audit: audit,
          replace: false
        )

      assert release.publisher_id == user.id
    end

    test "can't publish reserved package name", %{user: user} do
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
                 "123abc",
                 "123abc",
                 audit: audit,
                 replace: false
               )

      assert %{name: "is reserved"} = errors_on(changeset)
    end

    test "can't publish reserved package version", %{package: package, user: user} do
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
                 "123abc",
                 "123abc",
                 audit: audit,
                 replace: false
               )

      assert %{version: "is reserved"} = errors_on(changeset)
    end

    test "can't publish using non-semantic version", %{package: package, user: user} do
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
                 "123abc",
                 "123abc",
                 audit: audit,
                 replace: false
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

    test "revert release and package removes artifacts", %{
      package: package,
      release: release,
      user: user
    } do
      Hexpm.Store.put(:repo_bucket, "tarballs/#{package.name}-#{release.version}.tar", "DATA", [])
      Hexpm.Store.put(:repo_bucket, "packages/#{package.name}", "DATA", [])

      audit = audit_data(user)
      assert Releases.revert(package, release, audit: audit) == :ok

      refute Hexpm.Store.get(:repo_bucket, "tarballs/#{package.name}-#{release.version}.tar", [])
      refute Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])
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

    test "revert release and package removes and updates artifacts", %{
      package: package,
      user: user
    } do
      Hexpm.Store.put(:repo_bucket, "tarballs/#{package.name}-0.2.0.tar", "DATA", [])

      audit = audit_data(user)
      release = insert(:release, package: package, version: "0.2.0")

      Hexpm.Repository.RegistryBuilder.package(package)

      assert Releases.revert(package, release, audit: audit) == :ok

      refute Hexpm.Store.get(:repo_bucket, "tarballs/#{package.name}-0.2.0.tar", [])
      assert registry = Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])

      assert Enum.any?(decode_registry_package(registry), &match?(%{version: "0.1.0"}, &1))
      refute Enum.any?(decode_registry_package(registry), &match?(%{version: "0.2.0"}, &1))
    end
  end

  defp decode_registry_package(registry) do
    assert {:ok, releases} =
             registry
             |> :zlib.gunzip()
             |> :hex_registry.decode_signed()
             |> Map.fetch!(:payload)
             |> :hex_registry.decode_package(:no_verify, :no_verify)

    releases
  end
end
