defmodule Hexpm.Repository.ReleasesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Releases

  setup do
    organization = insert(:organization)
    package = insert(:package, organization_id: organization.id)
    user = insert(:user)

    %{organization: organization, package: package, user: user}
  end

  describe "publish/7" do
    test "cant publish reserved package name", %{organization: organization, user: user} do
      Repo.insert_all("reserved_packages", [
        %{"organization_id" => organization.id, "name" => "reserved_name"}
      ])

      meta = default_meta("reserved_name", "0.1.0")
      audit = audit_data(user)

      assert {:error, :package, changeset, _} =
               Releases.publish(organization, nil, user, "BODY", meta, "CHECKSUM", audit: audit)

      assert %{name: "is reserved"} = errors_on(changeset)
    end

    test "cant publish reserved package version", %{
      organization: organization,
      package: package,
      user: user
    } do
      Repo.insert_all("reserved_packages", [
        %{"organization_id" => organization.id, "name" => package.name, "version" => "0.1.0"}
      ])

      meta = default_meta(package.name, "0.1.0")
      audit = audit_data(user)

      assert {:error, :release, changeset, _} =
               Releases.publish(
                 organization,
                 package,
                 user,
                 "BODY",
                 meta,
                 "CHECKSUM",
                 audit: audit
               )

      assert %{version: "is reserved"} = errors_on(changeset)
    end
  end
end
