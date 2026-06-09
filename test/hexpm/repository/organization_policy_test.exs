defmodule Hexpm.Repository.OrganizationPolicyTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.OrganizationPolicy

  describe "changeset/2" do
    test "requires name, visibility" do
      changeset = OrganizationPolicy.changeset(%OrganizationPolicy{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:name] == "can't be blank"
      assert errors[:visibility] == "can't be blank"
    end

    test "validates name format" do
      changeset =
        OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
          name: "-bad-start",
          visibility: "public"
        })

      refute changeset.valid?
      assert errors_on(changeset).name == "has invalid format"
    end

    test "validates name length 3..64" do
      assert errors_on(
               OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
                 name: "ab",
                 visibility: "public"
               })
             ).name == "should be at least 3 character(s)"

      assert errors_on(
               OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
                 name: String.duplicate("a", 65),
                 visibility: "public"
               })
             ).name == "should be at most 64 character(s)"
    end

    test "validates visibility inclusion" do
      changeset =
        OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
          name: "ok-name",
          visibility: "weird"
        })

      refute changeset.valid?
      assert errors_on(changeset).visibility == "is invalid"
    end

    test "accepts a minimal valid policy" do
      changeset =
        OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
          name: "strict-prod",
          visibility: "public"
        })

      assert changeset.valid?
    end

    test "casts repository tabs with restrictions and overrides" do
      changeset =
        OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
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
        OrganizationPolicy.changeset(%OrganizationPolicy{}, %{
          "name" => "strict-prod",
          "visibility" => "public",
          "repositories" => [%{"repository" => "hexpm", "cooldown" => "5x"}]
        })

      refute changeset.valid?
    end
  end
end
