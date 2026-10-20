defmodule Hexpm.WorkloadIdentities.WorkloadIdentityTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.WorkloadIdentities.{TrustedRepository, WorkloadIdentity}

  setup do
    user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])
    %{package: package}
  end

  describe "changeset/3" do
    test "requires provider, owner, repositories, and workflow", %{package: package} do
      changeset = WorkloadIdentity.changeset(%WorkloadIdentity{}, %{}, package)
      refute changeset.valid?

      assert %{provider: _, repository_owner: _, repositories: _, workflow: _} =
               errors_on(changeset)
    end

    test "normalizes workflow to filename and fills issuer", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
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
            "repositories" => "Widget",
            "workflow" => "release.yml"
          },
          package
        )

      assert changeset.valid?

      assert Ecto.Changeset.get_field(changeset, :repositories) == [
               %TrustedRepository{name: "acme/widget", id: nil}
             ]
    end

    test "preserves workflow and environment casing", %{package: package} do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
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
        "repositories" => "widget",
        "workflow" => "release.yml"
      }

      for {field, value} <- [
            repository_owner: String.duplicate("a", 40),
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
            "repositories" => "widget",
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
              "repositories" => "widget",
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
            "repositories" => "other/widget",
            "workflow" => "release.yml"
          },
          package
        )

      refute changeset.valid?

      assert "other/widget must be a repository of acme" in List.wrap(
               errors_on(changeset).repositories
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
          "repositories" => "widget"
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

    test "matches every repository of the owner for a read workload identity with no repositories",
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
      assert Ecto.Changeset.get_field(changeset, :repositories) == []
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
      assert Ecto.Changeset.get_field(changeset, :repositories) == []
    end

    test "requires a repository for the write role", %{organization: organization} do
      for params <- [%{}, %{"repositories" => ""}, %{"repositories" => " , \n"}] do
        changeset =
          WorkloadIdentity.changeset(
            %WorkloadIdentity{},
            Map.merge(
              %{
                "provider" => "github",
                "repository_owner" => "acme",
                "role" => "write",
                "workflow" => "release.yml"
              },
              params
            ),
            organization
          )

        assert "are required for the write role" in List.wrap(errors_on(changeset).repositories)
      end
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

  describe "changeset/3 repositories" do
    defp repositories_changeset(package, repositories) do
      WorkloadIdentity.changeset(
        %WorkloadIdentity{},
        %{
          "provider" => "github",
          "repository_owner" => "Acme",
          "repositories" => repositories,
          "workflow" => "release.yml"
        },
        package
      )
    end

    defp repositories(changeset), do: Ecto.Changeset.get_field(changeset, :repositories)

    defp repository_errors(changeset) do
      for {:repositories, {message, _opts}} <- changeset.errors, do: message
    end

    test "takes one repository per line or separated by commas, each with an optional ID", %{
      package: package
    } do
      changeset = repositories_changeset(package, "Widget\nacme/Gadget 123, tool\r\nkit  456")

      assert changeset.valid?

      assert repositories(changeset) == [
               %TrustedRepository{name: "acme/widget", id: nil},
               %TrustedRepository{name: "acme/gadget", id: "123"},
               %TrustedRepository{name: "acme/tool", id: nil},
               %TrustedRepository{name: "acme/kit", id: "456"}
             ]
    end

    test "takes a list of entries or of maps", %{package: package} do
      changeset = repositories_changeset(package, ["widget", "gadget 123"])

      assert repositories(changeset) == [
               %TrustedRepository{name: "acme/widget", id: nil},
               %TrustedRepository{name: "acme/gadget", id: "123"}
             ]

      changeset =
        repositories_changeset(package, [
          %{"name" => "Widget", "id" => 456},
          %{"name" => "gadget", "id" => "789"},
          %{"name" => "tool", "id" => ""},
          %{name: "kit"}
        ])

      assert changeset.valid?

      assert repositories(changeset) == [
               %TrustedRepository{name: "acme/widget", id: "456"},
               %TrustedRepository{name: "acme/gadget", id: "789"},
               %TrustedRepository{name: "acme/tool", id: nil},
               %TrustedRepository{name: "acme/kit", id: nil}
             ]
    end

    test "ignores empty entries", %{package: package} do
      changeset = repositories_changeset(package, "\n widget,, \n\n , gadget\n")

      assert changeset.valid?
      assert Enum.map(repositories(changeset), & &1.name) == ["acme/widget", "acme/gadget"]
    end

    test "refuses a repository of another owner", %{package: package} do
      for {entry, message} <- [
            {"other/widget", "other/widget must be a repository of acme"},
            {"acme/widget/extra", "acme/widget/extra must be a repository of acme"},
            {"/widget", "/widget must be a repository of acme"}
          ] do
        changeset = repositories_changeset(package, entry)

        refute changeset.valid?
        assert repository_errors(changeset) == [message]
      end
    end

    test "refuses invalid repository names", %{package: package} do
      long = String.duplicate("a", 101)

      for {entry, message} <- [
            {"wid$get", "wid$get must be a valid GitHub repository name"},
            {"acme/", "acme/ must be a valid GitHub repository name"},
            {long, "#{long} must be a valid GitHub repository name"}
          ] do
        changeset = repositories_changeset(package, entry)

        refute changeset.valid?
        assert repository_errors(changeset) == [message]
      end

      assert repositories_changeset(package, String.duplicate("a", 100)).valid?
    end

    test "refuses repository IDs that aren't positive numbers of at most 19 digits", %{
      package: package
    } do
      for entry <- [
            "widget abc",
            "widget 0123",
            "widget -1",
            "widget " <> String.duplicate("1", 20),
            %{"name" => "widget", "id" => 1.5}
          ] do
        changeset = repositories_changeset(package, [entry])

        refute changeset.valid?

        assert repository_errors(changeset) == [
                 "acme/widget must be followed by a numeric repository ID"
               ]
      end

      assert repositories_changeset(package, "widget " <> String.duplicate("9", 19)).valid?
    end

    test "refuses more than a name and an ID on a line", %{package: package} do
      changeset = repositories_changeset(package, "widget 123 456")

      assert repository_errors(changeset) == [
               "must have one repository per line, a name and an optional repository ID"
             ]
    end

    test "refuses a repository listed twice", %{package: package} do
      changeset = repositories_changeset(package, "widget\nAcme/Widget 123\ngadget, gadget")

      assert repository_errors(changeset) == [
               "must list each repository once, not acme/gadget, acme/widget again"
             ]
    end

    test "takes at most 50 repositories", %{package: package} do
      names = for n <- 1..50, do: "widget#{n}"

      assert repositories_changeset(package, Enum.join(names, "\n")).valid?

      changeset = repositories_changeset(package, Enum.join(["widget51" | names], "\n"))
      assert repository_errors(changeset) == ["must be at most 50 repositories"]
    end

    test "refuses repositories that aren't text or a list of entries", %{package: package} do
      for value <- [%{"name" => "widget"}, 123, [123], [nil]] do
        changeset = repositories_changeset(package, value)

        assert repository_errors(changeset) == ["must be a list of repositories"]
      end
    end

    test "requires a repository for a package workload identity", %{package: package} do
      for value <- ["", " , \n", [], nil] do
        changeset = repositories_changeset(package, value)

        assert repository_errors(changeset) == ["is required"]
      end
    end
  end

  describe "update_changeset/2" do
    test "changes a package workload identity's repositories, workflow and environment only", %{
      package: package
    } do
      identity =
        insert(:workload_identity,
          package: package,
          repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
          workflow: "release.yml"
        )

      changeset =
        WorkloadIdentity.update_changeset(identity, %{
          "provider" => "gitlab",
          "repository_owner" => "other",
          "role" => "read",
          "repositories" => "widget\ngadget 789",
          "workflow" => "publish.yml",
          "environment" => "release"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :provider) == "github"
      assert Ecto.Changeset.get_field(changeset, :repository_owner) == "acme"
      assert Ecto.Changeset.get_field(changeset, :role) == "write"
      assert Ecto.Changeset.get_field(changeset, :workflow) == "publish.yml"
      assert Ecto.Changeset.get_field(changeset, :environment) == "release"

      assert Ecto.Changeset.get_field(changeset, :repositories) == [
               %TrustedRepository{name: "acme/widget", id: nil},
               %TrustedRepository{name: "acme/gadget", id: "789"}
             ]
    end

    test "keeps the repositories without repositories in the params", %{package: package} do
      repositories = [%TrustedRepository{name: "acme/widget", id: "456"}]
      identity = insert(:workload_identity, package: package, repositories: repositories)

      changeset = WorkloadIdentity.update_changeset(identity, %{"workflow" => "publish.yml"})

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :repositories)
      assert Ecto.Changeset.get_field(changeset, :repositories) == repositories
    end

    test "requires a repository on a package workload identity", %{package: package} do
      identity = insert(:workload_identity, package: package)

      changeset = WorkloadIdentity.update_changeset(identity, %{"repositories" => ""})

      assert "is required" in List.wrap(errors_on(changeset).repositories)
    end

    test "changes an organization workload identity's packages but not its role" do
      organization = insert(:organization)

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "release.yml"
        )

      changeset =
        WorkloadIdentity.update_changeset(identity, %{
          "role" => "read",
          "repository_owner" => "other",
          "packages" => "widget, gadget",
          "covers_public" => "true",
          "public_packages" => "tool"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :role) == "write"
      assert Ecto.Changeset.get_field(changeset, :repository_owner) == "acme"
      assert Ecto.Changeset.get_field(changeset, :packages) == ["gadget", "widget"]
      assert Ecto.Changeset.get_field(changeset, :public_packages) == ["tool"]
    end

    test "requires a repository on an organization write workload identity" do
      identity =
        insert(:organization_workload_identity,
          organization: insert(:organization),
          role: "write",
          workflow: "release.yml"
        )

      changeset = WorkloadIdentity.update_changeset(identity, %{"repositories" => ""})

      assert "are required for the write role" in List.wrap(errors_on(changeset).repositories)
    end

    test "lets an organization read workload identity match every repository" do
      identity =
        insert(:organization_workload_identity,
          organization: insert(:organization),
          workflow: "ci.yml"
        )

      changeset =
        WorkloadIdentity.update_changeset(identity, %{"repositories" => "", "workflow" => ""})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :repositories) == []

      changeset = WorkloadIdentity.update_changeset(identity, %{"repositories" => ""})

      assert "must be empty when every repository matches" in List.wrap(
               errors_on(changeset).workflow
             )
    end
  end

  describe "put_immutable_ids/2" do
    defp new_changeset(package, repositories, params \\ %{}) do
      WorkloadIdentity.changeset(
        %WorkloadIdentity{},
        Map.merge(
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => repositories,
            "workflow" => "release.yml"
          },
          params
        ),
        package
      )
    end

    defp resolved(repositories, owner_id \\ 123) do
      %{repository_owner_id: owner_id, repositories: repositories}
    end

    defp pinned_repositories(changeset) do
      changeset
      |> Ecto.Changeset.get_field(:repositories)
      |> Enum.map(&{&1.name, &1.id})
    end

    test "pins the owner's ID and the repository IDs Hex reads", %{package: package} do
      changeset =
        package
        |> new_changeset("widget 999\ngadget 123")
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{
            "acme/widget" => %{id: 456, public: false},
            "acme/gadget" => %{id: nil, public: false}
          })
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :repository_owner_id) == "123"
      assert pinned_repositories(changeset) == [{"acme/widget", "456"}, {"acme/gadget", "123"}]
    end

    test "names a repository Hex can't see that has no ID", %{package: package} do
      changeset =
        package
        |> new_changeset("widget\ngadget")
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{
            "acme/widget" => %{id: nil, public: false},
            "acme/gadget" => %{id: nil, public: false}
          })
        )

      refute changeset.valid?

      assert repository_errors(changeset) == [
               "acme/widget needs its repository ID after the name, because Hex can't see it on GitHub",
               "acme/gadget needs its repository ID after the name, because Hex can't see it on GitHub"
             ]
    end

    test "requires an environment naming the public repositories on a write workload identity",
         %{package: package} do
      repositories =
        resolved(%{
          "acme/widget" => %{id: 1, public: true},
          "acme/gadget" => %{id: 2, public: true},
          "acme/tool" => %{id: 3, public: false}
        })

      changeset =
        package
        |> new_changeset("widget\ngadget\ntool")
        |> WorkloadIdentity.put_immutable_ids(repositories)

      assert errors_on(changeset).environment ==
               "is required because acme/widget, acme/gadget are public"

      changeset =
        package
        |> new_changeset("widget\ntool")
        |> WorkloadIdentity.put_immutable_ids(repositories)

      assert errors_on(changeset).environment == "is required because acme/widget is public"

      changeset =
        package
        |> new_changeset("widget\ntool", %{"environment" => "release"})
        |> WorkloadIdentity.put_immutable_ids(repositories)

      assert changeset.valid?

      changeset =
        package
        |> new_changeset("tool")
        |> WorkloadIdentity.put_immutable_ids(repositories)

      assert changeset.valid?
    end

    test "doesn't require an environment on a read workload identity" do
      changeset =
        WorkloadIdentity.changeset(
          %WorkloadIdentity{},
          %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "role" => "read"
          },
          insert(:organization)
        )
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{"acme/widget" => %{id: 1, public: true}})
        )

      assert changeset.valid?
    end

    test "keeps the pinned ID of a repository Hex can't see when changed", %{package: package} do
      identity =
        insert(:workload_identity,
          package: package,
          repository_owner_id: "123",
          repositories: [%TrustedRepository{name: "acme/widget", id: "456"}]
        )

      for entry <- ["widget", "widget 456"] do
        changeset =
          identity
          |> WorkloadIdentity.update_changeset(%{"repositories" => entry <> "\ngadget 789"})
          |> WorkloadIdentity.put_immutable_ids(
            resolved(%{
              "acme/widget" => %{id: nil, public: false},
              "acme/gadget" => %{id: nil, public: false}
            })
          )

        assert changeset.valid?
        assert pinned_repositories(changeset) == [{"acme/widget", "456"}, {"acme/gadget", "789"}]
      end
    end

    test "keeps the pinned ID GitHub reports again", %{package: package} do
      identity =
        insert(:workload_identity,
          package: package,
          repository_owner_id: "123",
          repositories: [%TrustedRepository{name: "acme/widget", id: "456"}]
        )

      changeset =
        identity
        |> WorkloadIdentity.update_changeset(%{"repositories" => "widget"})
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{"acme/widget" => %{id: 456, public: false}})
        )

      assert changeset.valid?
      assert pinned_repositories(changeset) == [{"acme/widget", "456"}]
      assert Ecto.Changeset.get_field(changeset, :repository_owner_id) == "123"
    end

    test "refuses a repository GitHub reports with a different ID than the pinned one", %{
      package: package
    } do
      identity =
        insert(:workload_identity,
          package: package,
          repository_owner_id: "123",
          repositories: [%TrustedRepository{name: "acme/widget", id: "456"}]
        )

      changeset =
        identity
        |> WorkloadIdentity.update_changeset(%{"repositories" => "widget"})
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{"acme/widget" => %{id: 789, public: false}})
        )

      assert repository_errors(changeset) == [
               "acme/widget was deleted and created again on GitHub since it was added. " <>
                 "Remove it and save, then add it again"
             ]
    end

    test "refuses a typed ID that differs from the pinned one", %{package: package} do
      identity =
        insert(:workload_identity,
          package: package,
          repository_owner_id: "123",
          repositories: [%TrustedRepository{name: "acme/widget", id: "456"}]
        )

      changeset =
        identity
        |> WorkloadIdentity.update_changeset(%{"repositories" => "widget 789"})
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{"acme/widget" => %{id: nil, public: false}})
        )

      assert repository_errors(changeset) == [
               "acme/widget has repository ID 456. " <>
                 "Remove it and save, then add it again with the new ID"
             ]
    end

    test "refuses an owner whose ID differs from the pinned one", %{package: package} do
      identity =
        insert(:workload_identity,
          package: package,
          repository_owner_id: "123",
          repositories: [%TrustedRepository{name: "acme/widget", id: "456"}]
        )

      changeset =
        identity
        |> WorkloadIdentity.update_changeset(%{})
        |> WorkloadIdentity.put_immutable_ids(
          resolved(%{"acme/widget" => %{id: 456, public: false}}, 999)
        )

      assert errors_on(changeset).repository_owner ==
               "is a different GitHub account than when the workload identity was added"
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

    test "refuse no repositories on a package workload identity", %{package: package} do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_repositories/, fn ->
        insert(:workload_identity, package: package, repositories: [])
      end
    end

    test "refuse no repositories on an organization write workload identity" do
      assert_raise Ecto.ConstraintError, ~r/workload_identities_repositories/, fn ->
        insert(:organization_workload_identity,
          role: "write",
          workflow: "a.yml",
          repositories: []
        )
      end
    end

    test "refuse a workflow or environment on an organization workload identity for every repository" do
      for attrs <- [[workflow: "ci.yml"], [environment: "ci"]] do
        assert_raise Ecto.ConstraintError, ~r/workload_identities_repositories/, fn ->
          insert(:organization_workload_identity, [repositories: []] ++ attrs)
        end
      end
    end

    test "refuse a repository without a name or a pinned ID", %{package: package} do
      for repository <- [
            %TrustedRepository{name: "acme/widget", id: nil},
            %TrustedRepository{name: "acme/widget", id: ""},
            %TrustedRepository{name: nil, id: "456"},
            %TrustedRepository{name: "", id: "456"}
          ] do
        assert_raise Ecto.ConstraintError, ~r/workload_identities_repositories/, fn ->
          insert(:workload_identity, package: package, repositories: [repository])
        end
      end
    end

    test "allow no repositories on an organization read workload identity" do
      assert %WorkloadIdentity{repositories: []} =
               insert(:organization_workload_identity, repositories: [])
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
