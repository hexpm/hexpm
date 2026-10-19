defmodule Hexpm.WorkloadIdentities.WorkloadIdentityTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  setup do
    user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])
    %{package: package}
  end

  describe "changeset/3" do
    test "requires provider, owner, repository, and workflow", %{package: package} do
      changeset = WorkloadIdentity.changeset(%WorkloadIdentity{}, %{}, package)
      refute changeset.valid?

      assert %{provider: _, repository_owner: _, repository: _, workflow: _} =
               errors_on(changeset)
    end

    test "normalizes workflow to filename and fills issuer", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => ".github/workflows/release.yml"
          },
          package
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :workflow) == "release.yml"
      assert Ecto.Changeset.get_field(changeset, :issuer) == WorkloadIdentity.github_issuer()
      assert Ecto.Changeset.get_field(changeset, :environment) == ""
    end

    test "qualifies a bare repository with the owner", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "Acme",
            "repository" => "Widget",
            "workflow" => "release.yml"
          },
          package
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :repository) == "acme/widget"
    end

    test "preserves workflow and environment casing", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => ".github/workflows/Release.yml",
            "environment" => "Production"
          },
          package
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :workflow) == "Release.yml"
      assert Ecto.Changeset.get_field(changeset, :environment) == "Production"
    end

    test "bounds every user-supplied field to its column", %{package: package} do
      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repository" => "widget",
        "workflow" => "release.yml"
      }

      for {field, value} <- [
            repository_owner: String.duplicate("a", 40),
            repository: String.duplicate("a", 136),
            repository_id: String.duplicate("1", 20),
            workflow: String.duplicate("a", 252) <> ".yml",
            environment: String.duplicate("é", 256)
          ] do
        changeset =
          WorkloadIdentity.changeset(
            %WorkloadIdentity{},
            Map.put(params, to_string(field), value),
            package
          )

        assert Enum.any?(changeset.errors, fn {error_field, {_, opts}} ->
                 error_field == field and opts[:validation] == :length
               end)
      end
    end

    test "accepts an environment of 255 characters", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml",
            "environment" => String.duplicate("é", 255)
          },
          package
        )

      assert changeset.valid?
    end

    test "rejects an environment with control characters", %{package: package} do
      for environment <- [
            "production\n\nReset your password at https://example.com/reset",
            "production\r\nNotice",
            "production\u0000"
          ] do
        changeset =
          WorkloadIdentity.changeset(
            %WorkloadIdentity{},
            %{
              "provider" => "github",
              "repository_owner" => "acme",
              "repository" => "widget",
              "workflow" => "release.yml",
              "environment" => environment
            },
            package
          )

        assert Map.has_key?(errors_on(changeset), :environment),
               "accepted environment #{inspect(environment)}"
      end
    end

    test "rejects repository owned by a different owner", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "other/widget",
            "workflow" => "release.yml"
          },
          package
        )

      refute changeset.valid?

      assert "must be a valid GitHub repository owned by repository_owner" in List.wrap(
               errors_on(changeset).repository
             )
    end
  end

  describe "changeset/3 for an organization" do
    setup do
      %{organization: insert(:organization)}
    end

    defp organization_params(params) do
      Map.merge(
        %{
          "provider" => "github",
          "repository_owner" => "acme",
          "repository" => "widget"
        },
        params
      )
    end

    test "stores an empty workflow for the read role", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{"role" => "read", "workflow" => ""}),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :workflow) == ""
    end

    test "requires a workflow for the write role", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{"role" => "write"}),
          organization
        )

      assert "is required for the write role" in List.wrap(errors_on(changeset).workflow)
    end

    test "rejects an unknown role", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{"role" => "admin", "workflow" => "release.yml"}),
          organization
        )

      assert errors_on(changeset).role
    end

    test "splits, deduplicates and sorts package names", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "packages" => "widget_core, gadget\nwidget_core"
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :packages) == ["gadget", "widget_core"]
    end

    test "stores no package names as every package", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "packages" => " , "
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :packages) == nil
    end

    test "rejects invalid package names", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "packages" => "Widget"
          }),
          organization
        )

      assert "must be valid package names" in List.wrap(errors_on(changeset).packages)
    end

    test "rejects an environment with control characters", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "environment" => "production\n\nReset your password at https://example.com/reset"
          }),
          organization
        )

      assert Map.has_key?(errors_on(changeset), :environment)
    end

    test "rejects a null package name", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "packages" => ["widget", nil]
          }),
          organization
        )

      assert "must be valid package names" in List.wrap(errors_on(changeset).packages)
    end

    test "matches every repository of the owner for a read workload identity with no repository",
         %{
           organization: organization
         } do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{"provider" => "github", "repository_owner" => "Acme", "role" => "read"},
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :repository) == ""
      assert Ecto.Changeset.get_field(changeset, :repository_id) == ""
      assert Ecto.Changeset.get_field(changeset, :workflow) == ""
    end

    test "rejects a workflow or environment when every repository matches", %{
      organization: organization
    } do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "role" => "read",
            "workflow" => "ci.yml",
            "environment" => "ci"
          },
          organization
        )

      errors = errors_on(changeset)
      assert "must be empty when every repository matches" in List.wrap(errors.workflow)
      assert "must be empty when every repository matches" in List.wrap(errors.environment)
      assert Ecto.Changeset.get_field(changeset, :workflow) == "ci.yml"
      assert Ecto.Changeset.get_field(changeset, :repository) == nil
    end

    test "rejects a repository ID when every repository matches", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "role" => "read",
            "repository_id" => "123"
          },
          organization
        )

      assert "must be empty when every repository matches" in List.wrap(
               errors_on(changeset).repository_id
             )

      assert Ecto.Changeset.get_field(changeset, :repository_id) == "123"
    end

    test "requires a repository for the write role", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "role" => "write",
            "workflow" => "release.yml"
          },
          organization
        )

      assert "is required for the write role" in List.wrap(errors_on(changeset).repository)
    end

    test "ignores package names for the read role", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{"role" => "read", "packages" => "widget"}),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :packages) == nil
    end

    test "rejects package names a package can't be created with", %{
      organization: organization
    } do
      for name <- ["a", "elixir", "Widget"] do
        changeset =
          WorkloadIdentity.changeset(
            %WorkloadIdentity{},
            organization_params(%{"role" => "write", "packages" => "widget, #{name}"}),
            organization
          )

        assert "must be valid package names" in List.wrap(errors_on(changeset).packages)
      end
    end

    test "covers every private package and no public package by default", %{
      organization: organization
    } do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{"role" => "write", "workflow" => "release.yml"}),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :covers_private) == true
      assert Ecto.Changeset.get_field(changeset, :packages) == nil
      assert Ecto.Changeset.get_field(changeset, :covers_public) == false
      assert Ecto.Changeset.get_field(changeset, :public_packages) == nil
    end

    test "stores an empty private list without private coverage", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "false",
            "packages" => "widget",
            "covers_public" => "true"
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :covers_private) == false
      assert Ecto.Changeset.get_field(changeset, :packages) == []
    end

    test "splits, deduplicates and sorts public package names", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_public" => "true",
            "public_packages" => "widget_core, gadget\nwidget_core"
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :public_packages) == ["gadget", "widget_core"]
    end

    test "stores no public package names as every owned package", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_public" => "true",
            "public_packages" => " , "
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :public_packages) == nil
    end

    test "ignores public package names without public coverage", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_public" => "false",
            "public_packages" => "widget"
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :public_packages) == nil
    end

    test "takes public package names a new package can't have, which ownership checks later", %{
      organization: organization
    } do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_public" => "true",
            "public_packages" => "widget, Gadget, stats"
          }),
          organization
        )

      refute Map.has_key?(errors_on(changeset), :public_packages)

      assert Ecto.Changeset.get_field(changeset, :public_packages) ==
               ["Gadget", "stats", "widget"]
    end

    test "rejects public package names no package can have", %{organization: organization} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_public" => "true",
            "public_packages" => String.duplicate("a", 256)
          }),
          organization
        )

      assert "must be valid package names" in List.wrap(errors_on(changeset).public_packages)
    end

    test "requires private packages, public packages or both for the write role", %{
      organization: organization
    } do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "false",
            "covers_public" => "false"
          }),
          organization
        )

      assert errors_on(changeset).covers_private ==
               "select private packages, public packages or both"
    end

    test "refuses private packages and the read role without active billing" do
      organization = insert(:organization, billing_active: false, trial_end: nil)

      params = %{"role" => "write", "workflow" => "release.yml", "covers_public" => "true"}

      changeset =
        WorkloadIdentity.changeset(%WorkloadIdentity{}, organization_params(params), organization)

      assert errors_on(changeset).covers_private ==
               "private packages need an active billing subscription"

      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{"role" => "read"}),
          organization
        )

      assert errors_on(changeset).role == "needs an active billing subscription"

      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(Map.put(params, "covers_private", "false")),
          organization
        )

      assert changeset.valid?
    end

    test "covers the repository and no public package for the read role", %{
      organization: organization
    } do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          organization_params(%{
            "role" => "read",
            "covers_private" => "false",
            "covers_public" => "true",
            "public_packages" => "widget"
          }),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :covers_private) == true
      assert Ecto.Changeset.get_field(changeset, :packages) == nil
      assert Ecto.Changeset.get_field(changeset, :covers_public) == false
      assert Ecto.Changeset.get_field(changeset, :public_packages) == nil
    end
  end

  describe "covers_private_package?/2" do
    test "needs private coverage and a list that is empty or names the package" do
      identity = %WorkloadIdentity{organization_id: 1, role: "write"}

      assert WorkloadIdentity.covers_private_package?(identity, "widget")

      assert WorkloadIdentity.covers_private_package?(
               %{identity | packages: ["widget"]},
               "widget"
             )

      refute WorkloadIdentity.covers_private_package?(%{identity | packages: ["other"]}, "widget")

      refute WorkloadIdentity.covers_private_package?(
               %{identity | covers_private: false, packages: []},
               "widget"
             )

      refute WorkloadIdentity.covers_private_package?(
               %{identity | covers_private: false, packages: nil},
               "widget"
             )

      refute WorkloadIdentity.covers_private_package?(%{identity | role: "read"}, "widget")

      refute WorkloadIdentity.covers_private_package?(
               %{identity | organization_id: nil},
               "widget"
             )
    end
  end

  describe "database constraints" do
    test "refuse public coverage on a read workload identity" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_public_coverage/, fn ->
        insert(:organization_workload_identity, covers_public: true)
      end
    end

    test "refuse a workload identity that covers nothing" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_private_coverage/, fn ->
        insert(:organization_workload_identity,
          role: "write",
          workflow: "a.yml",
          covers_private: false,
          packages: []
        )
      end
    end

    test "refuse a null private list without private coverage" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_private_coverage/, fn ->
        insert(:organization_workload_identity,
          role: "write",
          workflow: "a.yml",
          covers_private: false,
          covers_public: true
        )
      end
    end

    test "refuse an empty private list with private coverage" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_packages/, fn ->
        insert(:organization_workload_identity, role: "write", workflow: "a.yml", packages: [])
      end
    end

    test "refuse a public list without public coverage" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_public_packages/, fn ->
        insert(:organization_workload_identity,
          role: "write",
          workflow: "a.yml",
          public_packages: ["widget"]
        )
      end
    end

    test "refuse an empty workflow on a package workload identity", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_workflow/, fn ->
        insert(:workload_identity, package: package, workflow: "")
      end
    end

    test "refuse an empty workflow on an organization write workload identity" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_workflow/, fn ->
        insert(:organization_workload_identity, role: "write", workflow: "")
      end
    end

    test "refuse an empty repository on a package workload identity", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_repository/, fn ->
        insert(:workload_identity, package: package, repository: "", repository_id: "")
      end
    end

    test "refuse a workflow on an organization workload identity for every repository" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_repository/, fn ->
        insert(:organization_workload_identity,
          repository: "",
          repository_id: "",
          workflow: "ci.yml"
        )
      end
    end

    test "refuse a workload identity with both a package and an organization", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_package_or_organization/, fn ->
        insert(:organization_workload_identity,
          package: package,
          role: "write",
          workflow: "a.yml"
        )
      end
    end
  end
end
