defmodule Hexpm.Repository.PolicyTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Policy

  describe "changeset/2" do
    test "requires name, visibility" do
      changeset = Policy.changeset(%Policy{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:name] == "can't be blank"
      assert errors[:visibility] == "can't be blank"
    end

    test "validates name format" do
      changeset =
        Policy.changeset(%Policy{}, %{
          name: "-bad-start",
          visibility: "public"
        })

      refute changeset.valid?
      assert errors_on(changeset).name == "has invalid format"
    end

    test "validates name length 3..64" do
      assert errors_on(
               Policy.changeset(%Policy{}, %{
                 name: "ab",
                 visibility: "public"
               })
             ).name == "should be at least 3 character(s)"

      assert errors_on(
               Policy.changeset(%Policy{}, %{
                 name: String.duplicate("a", 65),
                 visibility: "public"
               })
             ).name == "should be at most 64 character(s)"
    end

    test "validates visibility inclusion" do
      changeset =
        Policy.changeset(%Policy{}, %{
          name: "ok-name",
          visibility: "weird"
        })

      refute changeset.valid?
      assert errors_on(changeset).visibility == "is invalid"
    end

    test "accepts a minimal valid policy" do
      changeset =
        Policy.changeset(%Policy{}, %{
          name: "strict-prod",
          visibility: "public"
        })

      assert changeset.valid?
    end

    test "casts repository tabs with restrictions and overrides" do
      changeset =
        Policy.changeset(%Policy{}, %{
          "name" => "strict-prod",
          "visibility" => "public",
          "repositories" => [
            %{
              "repository" => "hexpm",
              "cooldown" => "14d",
              "advisory_min_severity" => 3,
              "retirement_reasons" => [1, 2],
              "overrides" => [
                %{"action" => "deny", "package" => "badlib"},
                %{"action" => "allow", "package" => "phoenix", "requirement" => "== 1.7.10"}
              ]
            },
            %{"repository" => "myorg"}
          ]
        })

      assert changeset.valid?
      policy = Ecto.Changeset.apply_changes(changeset)

      assert [hexpm, myorg] = policy.repositories
      assert hexpm.repository == "hexpm"
      assert hexpm.cooldown == "14d"
      assert hexpm.advisory_min_severity == 3
      assert hexpm.retirement_reasons == [1, 2]
      assert [deny, allow] = hexpm.overrides
      assert deny.action == "deny"
      assert deny.package == "badlib"
      assert allow.requirement == "== 1.7.10"
      assert myorg.repository == "myorg"
      assert myorg.overrides == []
    end

    test "surfaces nested restriction errors" do
      changeset =
        Policy.changeset(%Policy{}, %{
          "name" => "strict-prod",
          "visibility" => "public",
          "repositories" => [%{"repository" => "hexpm", "cooldown" => "5x"}]
        })

      refute changeset.valid?
    end

    test "rejects reserved names that would shadow policy routes" do
      for name <- ~w(new package-suggestions version-suggestions) do
        changeset =
          Policy.changeset(%Policy{}, %{
            name: name,
            visibility: "public"
          })

        refute changeset.valid?, "expected #{name} to be rejected"
        assert errors_on(changeset).name == "is reserved"
      end
    end

    test "does not allow renaming an existing policy" do
      policy = %Policy{id: 1, name: "strict-prod", visibility: "public"}

      changeset = Policy.changeset(policy, %{name: "renamed", visibility: "public"})

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :name)
      assert Ecto.Changeset.apply_changes(changeset).name == "strict-prod"
    end

    test "still allows editing description and visibility of an existing policy" do
      policy = %Policy{id: 1, name: "strict-prod", visibility: "public"}

      changeset =
        Policy.changeset(policy, %{
          name: "renamed",
          description: "updated",
          visibility: "private"
        })

      assert changeset.valid?
      assert changeset.changes.description == "updated"
      assert changeset.changes.visibility == "private"
    end
  end
end
