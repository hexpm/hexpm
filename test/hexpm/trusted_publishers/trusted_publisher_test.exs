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
end
