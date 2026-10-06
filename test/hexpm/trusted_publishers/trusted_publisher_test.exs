defmodule Hexpm.TrustedPublishers.TrustedPublisherTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.TrustedPublishers.TrustedPublisher

  setup do
    user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])
    %{package: package}
  end

  describe "changeset/3" do
    test "requires provider, owner, repository, and workflow", %{package: package} do
      changeset = TrustedPublisher.changeset(%TrustedPublisher{}, %{}, package)
      refute changeset.valid?

      assert %{provider: _, repository_owner: _, repository: _, workflow: _} =
               errors_on(changeset)
    end

    test "normalizes workflow to filename and fills issuer", %{package: package} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
      assert Ecto.Changeset.get_field(changeset, :issuer) == TrustedPublisher.github_issuer()
      assert Ecto.Changeset.get_field(changeset, :environment) == ""
    end

    test "qualifies a bare repository with the owner", %{package: package} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
          TrustedPublisher.changeset(
            %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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

    test "rejects repository owned by a different owner", %{package: package} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
          organization_params(%{"role" => "read", "workflow" => ""}),
          organization
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :workflow) == ""
    end

    test "requires a workflow for the write role", %{organization: organization} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
          organization_params(%{"role" => "write"}),
          organization
        )

      assert "is required for the write role" in List.wrap(errors_on(changeset).workflow)
    end

    test "rejects an unknown role", %{organization: organization} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
          organization_params(%{"role" => "admin", "workflow" => "release.yml"}),
          organization
        )

      assert errors_on(changeset).role
    end

    test "splits, deduplicates and sorts package names", %{organization: organization} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "packages" => "Widget"
          }),
          organization
        )

      assert "must be valid package names" in List.wrap(errors_on(changeset).packages)
    end

    test "rejects a null package name", %{organization: organization} do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
          organization_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "packages" => ["widget", nil]
          }),
          organization
        )

      assert "must be valid package names" in List.wrap(errors_on(changeset).packages)
    end

    test "matches every repository of the owner for a read publisher with no repository", %{
      organization: organization
    } do
      changeset =
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
        TrustedPublisher.changeset(
          %TrustedPublisher{},
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
          TrustedPublisher.changeset(
            %TrustedPublisher{},
            organization_params(%{"role" => "write", "packages" => "widget, #{name}"}),
            organization
          )

        assert "must be valid package names" in List.wrap(errors_on(changeset).packages)
      end
    end
  end

  describe "database constraints" do
    test "refuse an empty workflow on a package publisher", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/trusted_publishers_workflow/, fn ->
        insert(:trusted_publisher, package: package, workflow: "")
      end
    end

    test "refuse an empty workflow on an organization write publisher" do
      assert_raise Ecto.ConstraintError, ~r/trusted_publishers_workflow/, fn ->
        insert(:organization_trusted_publisher, role: "write", workflow: "")
      end
    end

    test "refuse an empty repository on a package publisher", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/trusted_publishers_repository/, fn ->
        insert(:trusted_publisher, package: package, repository: "", repository_id: "")
      end
    end

    test "refuse a workflow on an organization publisher for every repository" do
      assert_raise Ecto.ConstraintError, ~r/trusted_publishers_repository/, fn ->
        insert(:organization_trusted_publisher,
          repository: "",
          repository_id: "",
          workflow: "ci.yml"
        )
      end
    end

    test "refuse a publisher with both a package and an organization", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/trusted_publishers_package_or_organization/, fn ->
        insert(:organization_trusted_publisher,
          package: package,
          role: "write",
          workflow: "a.yml"
        )
      end
    end
  end
end
