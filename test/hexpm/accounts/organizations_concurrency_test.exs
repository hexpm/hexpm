defmodule Hexpm.Accounts.OrganizationsConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{Organizations, OrganizationUser, Seats}

  # Every assertion here fails if the seat lock in Hexpm.Accounts.Seats stops
  # being taken. Deleting `lock: "FOR NO KEY UPDATE"` from Seats.lock!/1 is the
  # check that these are contending on real connections and not quietly boxed.

  test "two adds cannot spend the same last seat" do
    committed(&build_context/0, fn context ->
      newcomers = [insert(:user), insert(:user)]

      results =
        race(newcomers, fn user ->
          Organizations.add_member(context.organization, user, %{"role" => "read"},
            audit: audit_data(context.admin)
          )
        end)

      assert Enum.count(results, &match?({:ok, %OrganizationUser{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :seats_exhausted}, &1)) == 1
      assert Seats.used(context.organization) == 3
    end)
  end

  test "two removals cannot empty the organization" do
    committed(&build_context/0, fn context ->
      results =
        race([context.admin, context.other_admin], fn user ->
          Organizations.remove_member(context.organization, user,
            audit: audit_data(context.admin)
          )
        end)

      assert Enum.count(results, &(&1 == :ok)) == 1
      assert Enum.count(results, &(&1 == {:error, :last_member})) == 1
      assert Seats.used(context.organization) == 1
    end)
  end

  test "two demotions cannot leave the organization without an admin" do
    committed(&build_context/0, fn context ->
      results =
        race([context.admin, context.other_admin], fn user ->
          Organizations.change_role(context.organization, user, %{"role" => "read"},
            audit: audit_data(context.admin)
          )
        end)

      assert Enum.count(results, &match?({:ok, %OrganizationUser{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :last_admin})) == 1
      assert admin_count(context.organization) == 1
    end)
  end

  test "an add and a reduction cannot both take the last seat" do
    committed(&build_context/0, fn context ->
      newcomer = insert(:user)

      results =
        race([
          fn ->
            Organizations.add_member(context.organization, newcomer, %{"role" => "read"},
              audit: audit_data(context.admin)
            )
          end,
          fn ->
            Seats.update_quantity(context.organization, 2, fn quantity ->
              {:ok, %{"quantity" => quantity}}
            end)
          end
        ])

      successes =
        Enum.count(results, fn
          {:ok, %OrganizationUser{}} -> true
          {:ok, %{"quantity" => _}} -> true
          _other -> false
        end)

      assert successes == 1
      assert Seats.used(context.organization) <= paid_seats(context.organization)
    end)
  end

  defp build_context do
    # Three paid seats and two members, so exactly one seat is free and the
    # membership set is one removal away from its last member.
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    other_admin = insert(:user)

    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: other_admin, role: "admin")

    %{organization: organization, admin: admin, other_admin: other_admin}
  end

  defp admin_count(organization) do
    Hexpm.RepoBase.aggregate(
      from(organization_user in OrganizationUser,
        where: organization_user.organization_id == ^organization.id,
        where: organization_user.role == "admin"
      ),
      :count
    )
  end

  defp paid_seats(organization) do
    Hexpm.RepoBase.get!(Hexpm.Accounts.Organization, organization.id).billing_seats
  end
end
